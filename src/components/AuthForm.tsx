"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { FormEvent, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type AuthMode = "login" | "signup";

export default function AuthForm({
  mode,
}: {
  mode: AuthMode;
}) {
  const router = useRouter();

  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    setBusy(true);
    setMessage("");

    try {
      const supabase = createClient();

      if (mode === "signup") {
        const { error } = await supabase.auth.signUp({
          email,
          password,
          options: {
            data: {
              full_name: name,
            },
          },
        });

        if (error) {
          throw error;
        }

        setMessage(
          "Account created. Check your email if confirmation is enabled.",
        );
      } else {
        const { error } =
          await supabase.auth.signInWithPassword({
            email,
            password,
          });

        if (error) {
          throw error;
        }

        router.push("/dashboard");
        router.refresh();
      }
    } catch (error) {
      setMessage(
        error instanceof Error
          ? error.message
          : "Something went wrong.",
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="phaseAuth">
      <form className="phaseAuthCard" onSubmit={submit}>
        <Link href="/" className="phaseLogo">
          <span>Z</span>
          Zivora
        </Link>

        <div>
          <p className="phaseEyebrow">
            {mode === "login"
              ? "WELCOME BACK"
              : "CREATE YOUR ACCOUNT"}
          </p>

          <h1>
            {mode === "login"
              ? "Sign in to Zivora"
              : "Create your workspace"}
          </h1>

          <p className="phaseAuthDescription">
            {mode === "login"
              ? "Continue creating and sharing workflow guides."
              : "Start documenting repeatable work with clear guides."}
          </p>
        </div>

        {mode === "signup" && (
          <label>
            Full name

            <input
              value={name}
              onChange={(event) =>
                setName(event.target.value)
              }
              placeholder="Your name"
              required
            />
          </label>
        )}

        <label>
          Email address

          <input
            type="email"
            value={email}
            onChange={(event) =>
              setEmail(event.target.value)
            }
            placeholder="you@example.com"
            required
          />
        </label>

        <label>
          Password

          <input
            type="password"
            minLength={6}
            value={password}
            onChange={(event) =>
              setPassword(event.target.value)
            }
            placeholder="At least 6 characters"
            required
          />
        </label>

        {message && (
          <p className="phaseMessage">{message}</p>
        )}

        <button type="submit" disabled={busy}>
          {busy
            ? "Please wait..."
            : mode === "login"
              ? "Sign in"
              : "Create account"}
        </button>

        <p className="phaseAuthSwitch">
          {mode === "login"
            ? "New to Zivora? "
            : "Already have an account? "}

          <Link
            href={
              mode === "login"
                ? "/signup"
                : "/login"
            }
          >
            {mode === "login"
              ? "Create an account"
              : "Sign in"}
          </Link>
        </p>
      </form>
    </main>
  );
}
