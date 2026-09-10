import type { Metadata } from "next";
import "./globals.css";
import "./app-nav.css";
import AppNav from "./components/app-nav";

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
      <body className="antialiased"><AppNav /><div className="app-content">{children}</div></body>
    </html>
  );
}
