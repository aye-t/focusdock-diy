import type { Metadata } from "next";
import { headers } from "next/headers";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });

export async function generateMetadata(): Promise<Metadata> {
  const requestHeaders = await headers();
  const host = requestHeaders.get("x-forwarded-host") || requestHeaders.get("host") || "localhost:3000";
  const protocol = requestHeaders.get("x-forwarded-proto") || (host.includes("localhost") ? "http" : "https");
  const imageUrl = `${protocol}://${host}/og.png`;
  return {
    title: "FocusDock · 把时间放回手里",
    description: "一款本机优先的专注计时与节律提醒 Web App。",
    manifest: "/manifest.webmanifest",
    appleWebApp: { capable: true, title: "FocusDock", statusBarStyle: "default" },
    openGraph: { title: "FocusDock · 把时间放回手里", description: "专注计时与节律提醒，在休息节点自然汇合。", images: [imageUrl], type: "website" },
    twitter: { card: "summary_large_image", title: "FocusDock", description: "专注计时 · 节律提醒", images: [imageUrl] },
  };
}

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="zh-CN"><body className={`${geistSans.variable} ${geistMono.variable}`}>{children}</body></html>;
}
