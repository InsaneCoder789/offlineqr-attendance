"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { LoginPage } from "@/components/LoginPage";
import { usePortalData } from "@/components/FacultyPortalProvider";

export default function Login() {
  const { facultyIdentity } = usePortalData();
  const router = useRouter();
  useEffect(() => { if (facultyIdentity) router.replace("/dashboard"); }, [facultyIdentity, router]);
  return facultyIdentity ? null : <LoginPage />;
}
