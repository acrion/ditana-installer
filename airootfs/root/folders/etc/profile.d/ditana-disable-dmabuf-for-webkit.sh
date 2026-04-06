# This script disables the DMA-BUF renderer for WebKitGTK applications
# on systems with NVIDIA graphics cards. The issue affects both proprietary
# and open-source NVIDIA drivers, causing rendering problems. Disabling DMA-BUF
# forces WebKit to use software rendering for stability.
export WEBKIT_DISABLE_DMABUF_RENDERER=1
