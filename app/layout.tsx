import type { Metadata } from "next";
import "./globals.css";
import GlobalAccountController from "./components/global-account-controller";

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
      <body className="antialiased">
        {children}
        <GlobalAccountController />
      </body>
    </html>
  );
}
