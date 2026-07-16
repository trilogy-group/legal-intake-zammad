# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Client-side attachment preview modal for the legacy desktop app.
# Renders docx (via the vendored docx-preview UMD), pdf (via PDF.js rendered to
# <canvas>), and plain text / markdown (as plain text) — all in the browser,
# reusing the bytes the browser already fetches for download. No backend change.
# PDF is drawn to a canvas with PDF.js (not an <iframe>/native plugin), so it is
# immune to browsers/Chrome policies that block embedded/blob PDFs.
class App.TicketZoomArticleAttachmentPreview extends App.ControllerModal
  buttonClose:  true
  buttonCancel: true
  buttonSubmit: __('Download')
  buttonClass:  'btn--success'
  head:         ''
  veryLarge:    true   # fixed width — consistent for pdf & docx
  shown:        false  # defer render until params are set (avoids double render)

  constructor: (params) ->
    super
    @previewType = params.previewType   # 'pdf' | 'docx' | 'text'
    # Strip any existing query string: the article-view builds attachment.url
    # with '?disposition=attachment' already, so appending another query would
    # produce '...?disposition=attachment?disposition=inline' (unparseable).
    @fileUrl     = (params.fileUrl or '').split('?')[0]
    @fileName    = params.fileName
    @head        = App.i18n.translateInline('Preview – %s', @fileName)
    # Fixed-size modal with pinned header/footer + scrollable body.
    @el.addClass('modal--attachmentPreview')
    @render()
    @loadPreview()

  content: ->
    $('<div class="attachment-preview-body js-previewBody"></div>').append(
      App.i18n.translateInline('Loading …')
    )

  loadPreview: =>
    body = @el.find('.js-previewBody')

    xhr = new XMLHttpRequest()
    # The attachment endpoint returns the raw bytes regardless of disposition;
    # we only consume the blob locally, so fetch the clean base URL.
    xhr.open('GET', @fileUrl, true)
    xhr.responseType = 'blob'
    xhr.withCredentials = true
    xhr.onload = =>
      if xhr.status < 200 or xhr.status >= 300
        return @showError(body)
      blob = xhr.response
      switch @previewType
        when 'pdf'
          @renderPdf(blob, body)
        when 'docx'
          body.empty()
          # window.docx = vendored docx-preview UMD; experimental renders
          # tracked changes / comments.
          options =
            inWrapper: true
            breakPages: true
            experimental: true
            ignoreLastRenderedPageBreak: true
          promise = window.docx.renderAsync(blob, body.get(0), null, options)
          promise.catch(=> @showError(body))
        else # text / markdown — plain text only (never HTML), XSS-safe
          reader = new FileReader()
          reader.onload = ->
            pre = $('<pre class="attachment-preview-text"></pre>')
            pre.text(reader.result)   # .text() escapes — no HTML injection
            body.empty().append(pre)
          reader.readAsText(blob)
    xhr.onerror = => @showError(body)
    xhr.send()

  # Render every page of the PDF to a <canvas> via PDF.js. Canvas rendering
  # needs no <iframe>, native PDF plugin, or 'blob:' frame — so it works
  # regardless of the user's browser PDF settings / managed policies.
  renderPdf: (blob, body) =>
    pdfjsLib = window.pdfjsLib
    return @showError(body) if !pdfjsLib
    onError = => @showError(body)
    # The worker is served same-origin from public/assets/ (nginx serves
    # /assets/* statically; covered by CSP script-src 'self').
    pdfjsLib.GlobalWorkerOptions.workerSrc = '/assets/pdfjs/pdf.worker.min.js'

    container = $('<div class="attachment-preview-pdf"></div>')
    body.empty().append(container)

    blob.arrayBuffer().then((buffer) ->
      loadingTask = pdfjsLib.getDocument(data: new Uint8Array(buffer))
      loadingTask.promise.then((pdf) ->
        renderPage = (pageNum) ->
          pdf.getPage(pageNum).then((page) ->
            viewport = page.getViewport(scale: 1.5)
            canvas = document.createElement('canvas')
            canvas.className = 'attachment-preview-pdf-page'
            canvas.width = viewport.width
            canvas.height = viewport.height
            container.append(canvas)
            page.render(canvasContext: canvas.getContext('2d'), viewport: viewport).promise.then(->
              renderPage(pageNum + 1) if pageNum < pdf.numPages
            )
          )
        renderPage(1)
      ).catch(onError)
    ).catch(onError)

  showError: (body) ->
    body.text(App.i18n.translateInline('Preview could not be generated.'))

  onSubmit: =>
    window.open("#{@fileUrl}?disposition=attachment", '_blank')

  onClose: =>
    window.URL.revokeObjectURL(@pdfBlobUrl) if @pdfBlobUrl
