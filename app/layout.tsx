import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Variable Compensation Tracker",
  description: "Engagifii variable compensation management and employee earnings portal.",
  icons: {
    icon: "/favicon.svg",
    shortcut: "/favicon.svg",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className="antialiased">{children}</body>
    </html>
  );
}
