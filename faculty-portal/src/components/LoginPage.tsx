"use client";

import Image from "next/image";
import { Icon } from "./Icons";
import { useFacultyPortal } from "./FacultyPortalProvider";

export function LoginPage() {
  const {
    error,
    loginEmail,
    loginLoading,
    loginPassword,
    setLoginEmail,
    setLoginPassword,
    submitFacultyLogin,
  } = useFacultyPortal();

  return (
    <main className="login-page">
      <section className="login-card">
        <Image src="/branding/kiit_logo.png" alt="KIIT University" className="login-logo" width={96} height={96} priority />
        <p className="eyeline">KIIT Faculty Portal</p>
        <h1>Sign in to your attendance workspace</h1>
        <p>Use your KIIT faculty email and password to load only your classes, rosters, and attendance sessions.</p>
        <label className="login-field">
          <span>KIIT faculty email</span>
          <input
            type="email"
            value={loginEmail}
            placeholder="name@kiit.ac.in"
            autoComplete="username"
            onChange={(event) => setLoginEmail(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === "Enter" && !loginLoading) void submitFacultyLogin();
            }}
          />
        </label>
        <label className="login-field">
          <span>Password</span>
          <input
            type="password"
            value={loginPassword}
            placeholder="Password"
            autoComplete="current-password"
            onChange={(event) => setLoginPassword(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === "Enter" && !loginLoading) void submitFacultyLogin();
            }}
          />
        </label>
        {error ? (
          <div className="notice error" role="alert">
            <Icon name="alert" />
            <span>{error}</span>
          </div>
        ) : null}
        <button disabled={loginLoading} onClick={() => void submitFacultyLogin()}>
          <Icon name="check" />
          {loginLoading ? "Signing in..." : "Open faculty dashboard"}
        </button>
        <small>Your access is limited to faculty identity and assignments authorized by KIIT.</small>
      </section>
    </main>
  );
}
