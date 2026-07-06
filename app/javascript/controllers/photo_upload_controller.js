import { Controller } from "@hotwired/stimulus"

// 사진 업로드 전 캔버스 기반 클라이언트 압축 + 미리보기. 압축이 불가능한
// 환경에서는 원본을 그대로 전송한다(그레이스풀). (P3.4)
export default class extends Controller {
  static targets = ["input", "canvas", "preview"]
  static values = { maxWidth: { type: Number, default: 1600 }, quality: { type: Number, default: 0.8 } }

  preview() {
    const file = this.inputTarget.files && this.inputTarget.files[0]
    if (!file) return

    const url = URL.createObjectURL(file)
    const image = new Image()
    image.onload = () => {
      this.showPreview(url)
      this.compress(image, file)
    }
    image.onerror = () => this.showPreview(url)
    image.src = url
  }

  showPreview(url) {
    if (!this.hasPreviewTarget) return
    this.previewTarget.src = url
    this.previewTarget.classList.remove("hidden")
  }

  compress(image, file) {
    if (!this.hasCanvasTarget || typeof DataTransfer === "undefined") return

    const scale = Math.min(1, this.maxWidthValue / image.width)
    const canvas = this.canvasTarget
    canvas.width = Math.round(image.width * scale)
    canvas.height = Math.round(image.height * scale)
    canvas.getContext("2d").drawImage(image, 0, 0, canvas.width, canvas.height)

    canvas.toBlob(
      (blob) => {
        if (!blob || blob.size >= file.size) return
        const compressed = new File([blob], file.name, { type: "image/jpeg" })
        const transfer = new DataTransfer()
        transfer.items.add(compressed)
        this.inputTarget.files = transfer.files
      },
      "image/jpeg",
      this.qualityValue
    )
  }
}
