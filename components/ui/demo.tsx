import HalftoneWordmarkFooter from "@/components/ui/halftone-wordmark-footer"

export default function Demo() {
  return (
    <div className="w-full">
      <HalftoneWordmarkFooter
        wordmark="nearby drop"
        label="Nearby Drop"
        meta="Independent project · ©2026"
        preset="night"
        palette={{ background: "#17141c", ink: "#f4f1f6", warm: "#d24ada" }}
        height="500px"
        columns={[
          { title: "Download", links: [
            { label: "Latest release", href: "https://github.com/arslanbasharat-o-o/NearByDrop/releases/latest" },
            { label: "Source code", href: "https://github.com/arslanbasharat-o-o/NearByDrop" },
            { label: "Get help", href: "https://github.com/arslanbasharat-o-o/NearByDrop/issues" },
          ] },
          { title: "Guides", links: [
            { label: "Receive files", href: "blog/how-to-transfer-files-mac-android.html" },
            { label: "Send files", href: "blog/mac-to-android-quick-share.html" },
            { label: "Troubleshooting", href: "#troubleshooting" },
          ] },
          { title: "Project", links: [
            { label: "Tested devices", href: "device-verification.html" },
            { label: "GitHub", href: "https://github.com/arslanbasharat-o-o/NearByDrop" },
          ] },
          { title: "Legal", links: [
            { label: "Privacy", href: "legal/privacy.html" },
            { label: "Terms", href: "legal/terms.html" },
            { label: "Security", href: "legal/security.html" },
            { label: "Licenses", href: "legal/licenses.html" },
          ] },
        ]}
      />
    </div>
  )
}
