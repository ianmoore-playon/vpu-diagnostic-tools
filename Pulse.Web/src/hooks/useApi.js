import { useState, useEffect, useCallback, useRef } from "react";

const API_BASE = "/api";

export function useApi(path, { autoFetch = true, interval = 0 } = {}) {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const controllerRef = useRef(null);

  const fetch_ = useCallback(async () => {
    controllerRef.current?.abort();
    const controller = new AbortController();
    controllerRef.current = controller;
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`${API_BASE}${path}`, {
        signal: controller.signal,
      });
      if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
      const json = await res.json();
      setData(json);
      return json;
    } catch (err) {
      if (err.name !== "AbortError") {
        setError(err.message);
      }
      return null;
    } finally {
      setLoading(false);
    }
  }, [path]);

  useEffect(() => {
    if (!autoFetch) return;
    fetch_();
    if (interval > 0) {
      const id = setInterval(fetch_, interval);
      return () => clearInterval(id);
    }
    return () => controllerRef.current?.abort();
  }, [fetch_, autoFetch, interval]);

  return { data, loading, error, refetch: fetch_ };
}

export async function apiPost(path, body) {
  const res = await fetch(`${API_BASE}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => res.statusText);
    throw new Error(text);
  }
  return res.json();
}
