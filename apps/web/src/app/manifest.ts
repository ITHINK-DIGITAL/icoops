import type { MetadataRoute } from "next";

// PWA shell (D9). Offline queue and service worker arrive with the teller slice.
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "iCOOPs",
    short_name: "iCOOPs",
    description: "Cooperative management for staff",
    start_url: "/",
    display: "standalone",
    background_color: "#fafaf9",
    theme_color: "#0f766e",
    icons: [{ src: "/icons/icon.svg", sizes: "any", type: "image/svg+xml", purpose: "any" }],
  };
}
