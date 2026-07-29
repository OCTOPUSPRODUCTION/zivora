import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Zivora",
  description: "Create and share step-by-step workflow guides.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
