import type { Metadata } from "next";
import "./ui/tokens.css";
import "./ui/ui.css";
import "./globals.css";
import "./app-nav.css";
import "./revos-shell.css";
import "./page-shell.css";
import "./plan-workspace.css";
import "./plan-builder-v2.css";
import "./legacy-revos-overrides.css";
import AppNav from "./components/app-nav";
import RevOSTopBar from "./components/revos-topbar";

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
      <body className="antialiased"><RevOSTopBar/><AppNav/><div className="app-content">{children}</div></body>
    </html>
  );
}
