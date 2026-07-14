<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed } from 'vue'

import CommonFilePreview from '#shared/components/CommonFilePreview/CommonFilePreview.vue'
import { type AttachmentWithUrls } from '#shared/composables/useAttachments.ts'
import type { TicketArticle } from '#shared/entities/ticket/types.ts'
import type { FilePreview } from '#shared/utils/files.ts'

interface Props {
  article: TicketArticle
  articleAttachments: AttachmentWithUrls[]
}

const props = defineProps<Props>()

defineEmits<{
  preview: [type: FilePreview, image: AttachmentWithUrls]
}>()

const downloadAllUrl = computed(
  () => `/ticket_attachment_zip_by_article/${props.article.internalId}`,
)
</script>

<template>
  <footer
    v-if="articleAttachments.length > 0"
    class="flex flex-col gap-1 bg-blue-300 p-3 dark:bg-stone-700"
  >
    <div class="flex flex-row items-center justify-between">
      <CommonLabel prefix-icon="paperclip" size="small">
        {{
          articleAttachments.length === 1
            ? $t('1 attached file')
            : $t('%s attached files', articleAttachments.length)
        }}
      </CommonLabel>
      <CommonLink
        v-if="articleAttachments.length > 1"
        :link="downloadAllUrl"
        rest-api
        download
        class="flex items-center gap-1 text-xs text-blue-800 hover:text-blue-850 dark:hover:text-blue-600"
      >
        <CommonIcon size="tiny" decorative name="download" />
        {{ $t('Download all') }}
      </CommonLink>
    </div>
    <CommonFilePreview
      v-for="attachment of articleAttachments"
      :key="attachment.internalId"
      :download-url="attachment.downloadUrl"
      :preview-url="attachment.preview"
      :file="attachment"
      :no-preview="!$c.ui_ticket_zoom_attachments_preview"
      no-remove
      @preview="($event, type) => $emit('preview', type, attachment)"
    />
  </footer>
</template>
