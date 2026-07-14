// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import { renderComponent } from '#tests/support/components/index.ts'
import { mockApplicationConfig } from '#tests/support/mock-applicationConfig.ts'

import CommonFilePreview, {
  type Props,
} from '#shared/components/CommonFilePreview/CommonFilePreview.vue'

// This spec lives under apps/desktop so the test harness runs it in the
// "desktop" app context. The per-attachment Preview + Download buttons on
// CommonFilePreview are a desktop-only feature (mobile keeps image-only
// preview), so they can only be exercised from a desktop-located test.

const docxType =
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document'

const renderFilePreview = (props: Props & { onPreview?(event: Event): void }) => {
  return renderComponent(CommonFilePreview, {
    props,
    router: true,
    store: true,
  })
}

describe('CommonFilePreview desktop preview/download buttons', () => {
  beforeEach(() => {
    mockApplicationConfig({
      ui_ticket_zoom_attachments_preview: true,
      api_path: '/api',
      'active_storage.content_types_allowed_inline': ['image/png', 'image/jpeg'],
    })
  })

  it('shows a Preview button for a docx in a display context', () => {
    const view = renderFilePreview({
      file: { name: 'contract.docx', type: docxType, size: 2048 },
      downloadUrl: '/api/url',
      noRemove: true,
    })

    expect(view.getByRole('button', { name: 'Preview contract.docx' })).toBeInTheDocument()
  })

  it('emits preview with the resolved type on Preview click', async () => {
    const previewMock = vi.fn((event: Event) => event.preventDefault())
    const view = renderFilePreview({
      file: { name: 'contract.docx', type: docxType, size: 2048 },
      downloadUrl: '/api/url',
      noRemove: true,
      onPreview: previewMock,
    })

    await view.events.click(view.getByRole('button', { name: 'Preview contract.docx' }))

    expect(view.emitted().preview).toBeTruthy()
    const [, type] = view.emitted().preview![0] as [Event, string]
    expect(type).toBe('docx')
  })

  it('shows a Preview button for a PDF', () => {
    const view = renderFilePreview({
      file: { name: 'quote.pdf', type: 'application/pdf', size: 4096 },
      downloadUrl: '/api/url',
      noRemove: true,
    })

    expect(view.getByRole('button', { name: 'Preview quote.pdf' })).toBeInTheDocument()
  })

  it('does not show a Preview button for a non-previewable type (.doc)', () => {
    const view = renderFilePreview({
      file: { name: 'legacy.doc', type: 'application/msword', size: 2048 },
      downloadUrl: '/api/url',
      noRemove: true,
    })

    expect(view.queryByRole('button', { name: 'Preview legacy.doc' })).not.toBeInTheDocument()
  })

  it('does not show the buttons in an upload context (noRemove false)', () => {
    const view = renderFilePreview({
      file: { name: 'contract.docx', type: docxType, size: 2048 },
      downloadUrl: '/api/url',
    })

    expect(view.queryByRole('button', { name: 'Preview contract.docx' })).not.toBeInTheDocument()
  })
})
