import { useState, useEffect, useRef, useCallback } from "react";

export function useWebSocket(channels = []) {
  const [data, setData] = useState({});
  const [connected, setConnected] = useState(false);
  const wsRef = useRef(null);
  const channelsRef = useRef(channels);
  channelsRef.current = channels;

  const connect = useCallback(() => {
    const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
    const wsUrl = `${protocol}//${window.location.hostname}:5173/ws`;
    const ws = new WebSocket(wsUrl);
    wsRef.current = ws;

    ws.onopen = () => {
      setConnected(true);
      if (channelsRef.current.length > 0) {
        ws.send(JSON.stringify({ subscribe: channelsRef.current }));
      }
    };

    ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        if (msg.channel && msg.data) {
          setData((prev) => ({ ...prev, [msg.channel]: msg.data }));
        }
      } catch {}
    };

    ws.onclose = () => {
      setConnected(false);
      setTimeout(connect, 3000);
    };

    ws.onerror = () => ws.close();
  }, []);

  useEffect(() => {
    connect();
    return () => {
      wsRef.current?.close();
    };
  }, [connect]);

  useEffect(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN && channels.length > 0) {
      wsRef.current.send(JSON.stringify({ subscribe: channels }));
    }
  }, [channels]);

  return { data, connected };
}
