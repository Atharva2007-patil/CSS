import { useEffect, useState } from "react";
import { supabase } from "./lib/supabase";
import Login from "./pages/Login";
import Chat from "./pages/Chat";

function App() {
  // Keep session in state so we can switch between Login and Chat.
  const [session, setSession] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // Read current session when app loads.
    async function loadSession() {
      const { data } = await supabase.auth.getSession();
      setSession(data.session);
      setLoading(false);
    }

    loadSession();

    // Listen for login/logout changes and update session state.
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, newSession) => {
      setSession(newSession);
    });

    return () => {
      subscription.unsubscribe();
    };
  }, []);

  if (loading) {
    return <div className="centered-page">Loading...</div>;
  }

  // Show Login page if user is not authenticated.
  if (!session) {
    return <Login onLogin={setSession} />;
  }

  // Show Chat page after successful login.
  return <Chat session={session} />;
}

export default App;
