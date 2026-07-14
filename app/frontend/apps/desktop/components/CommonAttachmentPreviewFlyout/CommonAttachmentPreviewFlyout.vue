<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, shallowRef, useTemplateRef } from 'vue'

import { getAttachmentLinks } from '#shared/composables/getAttachmentLinks.ts'
import { useApplicationStore } from '#shared/stores/application.ts'
import type { FilePreview } from '#shared/utils/files.ts'
import openExternalLink from '#shared/utils/openExternalLink.ts'

import CommonFlyout from '#desktop/components/CommonFlyout/CommonFlyout.vue'
import CommonLoader from '#desktop/components/CommonLoader/CommonLoader.vue'

interface Props {
  fileInternalId: number
  fileType: string
  fileName: string
  previewType: Extract<FilePreview, 'pdf' | 'docx' | 'text'>
}

const props = defineProps<Props>()

const application = useApplicationStore()
const { downloadUrl, inlineUrl } = getAttachmentLinks(
  { internalId: props.fileInternalId, type: props.fileType },
  application.config.api_path,
)

const loading = ref(true)
const errorMessage = ref('')
const textContent = ref('')
const pdfBlobUrl = shallowRef<string>()
const docxTarget = useTemplateRef<HTMLElement>('docxTarget')

onMounted(async () => {
  try {
    // The browser already fetches attachment bytes for download; reuse that.
    // We only consume the bytes locally (blob / docx-preview / text), so the
    // server's Content-Disposition is irrelevant and no inline-serving change
    // is needed on the backend.
    const response = await fetch(inlineUrl, { credentials: 'same-origin' })
    if (!response.ok) throw new Error(`HTTP ${response.status}`)
    const blob = await response.blob()

    if (props.previewType === 'pdf') {
      pdfBlobUrl.value = URL.createObjectURL(
        new Blob([blob], { type: 'application/pdf' }),
      )
    } else if (props.previewType === 'text') {
      // text/plain and text/markdown — rendered as plain text (never HTML) to
      // avoid XSS from untrusted uploaded files.
      textContent.value = await blob.text()
    } else {
      // docx: renderAsync writes into a real DOM node. The target lives OUTSIDE
      // CommonLoader (which uses a <Transition mode="out-in"> that would delay
      // mounting the slot), kept in the DOM via v-show, so the ref is available
      // here immediately.
      const { renderAsync } = await import('docx-preview')
      if (!docxTarget.value) throw new Error('preview target not available')
      await renderAsync(blob, docxTarget.value, undefined, {
        inWrapper: true,
        breakPages: true,
        experimental: true, // render tracked changes / comments
        ignoreLastRenderedPageBreak: true,
      })
    }
  } catch (error) {
    errorMessage.value = (error as Error).message
  } finally {
    loading.value = false
  }
})

onBeforeUnmount(() => {
  if (pdfBlobUrl.value) URL.revokeObjectURL(pdfBlobUrl.value)
})

const downloadFile = () => {
  openExternalLink(downloadUrl, '_blank', props.fileName)
}
</script>

<template>
  <CommonFlyout
    :header-title="$t('Preview – %s', fileName)"
    :footer-action-options="{
      actionLabel: $t('Download'),
      actionButton: { variant: 'primary' },
    }"
    name="common-attachment-preview"
    size="large"
    no-close-on-action
    @action="downloadFile"
  >
    <CommonLoader :loading="loading">
      <CommonLabel v-if="errorMessage" class="text-red-500">
        {{ $t('Preview could not be generated.') }}
      </CommonLabel>

      <iframe
        v-else-if="previewType === 'pdf' && pdfBlobUrl"
        :src="pdfBlobUrl"
        class="h-[80vh] w-full border-0"
        :title="$t('Preview – %s', fileName)"
      />

      <pre
        v-else-if="previewType === 'text'"
        class="text-sm break-words whitespace-pre-wrap"
        >{{ textContent }}</pre
      >
    </CommonLoader>

    <!-- docx target lives outside CommonLoader (whose out-in Transition delays
         slot mounting) and stays in the DOM via v-show, so renderAsync always
         has a valid node to write into. -->
    <div
      v-show="previewType === 'docx' && !loading && !errorMessage"
      ref="docxTarget"
      class="attachment-docx-preview"
    />
  </CommonFlyout>
</template>

<style scoped>
.attachment-docx-preview {
  overflow: auto;
}
</style>
