<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, useTemplateRef } from 'vue'

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
const docxTarget = useTemplateRef<HTMLElement>('docxTarget')
const pdfTarget = useTemplateRef<HTMLElement>('pdfTarget')

// Render every page of the PDF to a <canvas> via PDF.js. Canvas rendering needs
// no <iframe>, native PDF plugin, or 'blob:' frame — so it works regardless of
// the user's browser PDF settings / managed policies (the reason we moved off
// the blob-iframe approach).
const renderPdf = async (blob: Blob, target: HTMLElement) => {
  const pdfjs = await import('pdfjs-dist/legacy/build/pdf')
  // Worker served same-origin from public/assets/ (nginx serves /assets/*
  // statically; covered by CSP script-src 'self').
  pdfjs.GlobalWorkerOptions.workerSrc = '/assets/pdfjs/pdf.worker.min.js'

  const buffer = await blob.arrayBuffer()
  const pdf = await pdfjs.getDocument({ data: new Uint8Array(buffer) }).promise

  for (let pageNum = 1; pageNum <= pdf.numPages; pageNum += 1) {
    // Sequential render keeps memory bounded and page order correct.
    const page = await pdf.getPage(pageNum)
    const viewport = page.getViewport({ scale: 1.5 })
    const canvas = document.createElement('canvas')
    canvas.className = 'attachment-preview-pdf-page'
    canvas.width = viewport.width
    canvas.height = viewport.height
    target.append(canvas)
    const context = canvas.getContext('2d')
    if (!context) continue
    await page.render({ canvasContext: context, viewport }).promise
  }
}

onMounted(async () => {
  try {
    // The browser already fetches attachment bytes for download; reuse that.
    // We only consume the bytes locally (PDF.js / docx-preview / text), so the
    // server's Content-Disposition is irrelevant and no inline-serving change
    // is needed on the backend.
    const response = await fetch(inlineUrl, { credentials: 'same-origin' })
    if (!response.ok) throw new Error(`HTTP ${response.status}`)
    const blob = await response.blob()

    if (props.previewType === 'text') {
      // text/plain and text/markdown — rendered as plain text (never HTML) to
      // avoid XSS from untrusted uploaded files.
      textContent.value = await blob.text()
    } else if (props.previewType === 'pdf') {
      if (!pdfTarget.value) throw new Error('preview target not available')
      await renderPdf(blob, pdfTarget.value)
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
  // Canvases are plain DOM children of the flyout; Vue tears them down with the
  // component. Nothing blob-URL-based to revoke anymore.
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

      <pre
        v-else-if="previewType === 'text'"
        class="text-sm break-words whitespace-pre-wrap"
        >{{ textContent }}</pre
      >
    </CommonLoader>

    <!-- pdf + docx targets live OUTSIDE CommonLoader (whose out-in Transition
         delays slot mounting) and stay in the DOM via v-show, so the imperative
         renderers (PDF.js / docx-preview) always have a valid node. -->
    <div
      v-show="previewType === 'pdf' && !loading && !errorMessage"
      ref="pdfTarget"
      class="attachment-preview-pdf"
    />
    <div
      v-show="previewType === 'docx' && !loading && !errorMessage"
      ref="docxTarget"
      class="attachment-docx-preview"
    />
  </CommonFlyout>
</template>

<style scoped>
.attachment-docx-preview,
.attachment-preview-pdf {
  overflow: auto;
}

.attachment-preview-pdf :deep(.attachment-preview-pdf-page) {
  display: block;
  margin: 0 auto 12px;
  max-width: 100%;
  height: auto;
}
</style>
