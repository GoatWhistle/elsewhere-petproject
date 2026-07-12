import React, { useState } from "react";
import { createRoot } from "react-dom/client";
import { createSession, generateFutures, Future } from "./api";
import "./styles.css";

function App() {
  const [dream, setDream] = useState("Устали вдвоём: тёплое море, тихо, вкусно, много ходить, до 180000 ₽");
  const [futures, setFutures] = useState<Future[]>([]);
  const [dna, setDna] = useState<Array<{ dimension: string; provenance: string }>>([]);
  const [loading, setLoading] = useState(false);
  const run = async () => { setLoading(true); try { const session = await createSession(dream); setDna(session.travel_dna.elements); setFutures((await generateFutures(session.id)).futures); } finally { setLoading(false); } };
  return <main>
    <header><span className="eyebrow">ELSEWHERE</span><h1>Увидьте поездку до бронирования.</h1><p>Опишите, как вы хотите себя чувствовать. Мы соберём несколько честных версий будущего.</p></header>
    <section className="dream"><textarea value={dream} onChange={e => setDream(e.target.value)} /><button onClick={run} disabled={loading}>{loading ? "Собираем…" : "Показать Futures"}</button></section>
    {dna.length > 0 && <section><h2>Ваш Travel DNA</h2><div className="chips">{dna.map(e => <span key={e.dimension}>{e.dimension} · {e.provenance}</span>)}</div></section>}
    <section><h2>Возможные будущие</h2><div className="grid">{futures.map(f => <article key={f.id}><div className="score">{Math.round(f.match.score * 100)}%</div><h3>{f.destination.name}</h3><p>{f.why_this_exists}</p><strong>{Math.round(f.price.total.amount_minor / 100).toLocaleString("ru-RU")} ₽</strong><small>Итог — estimate; проживание — modeled</small><details><summary>Почему такой match</summary>{f.match.contributions.map(c => <div key={c.dimension}>{c.dimension}: {c.contribution.toFixed(2)}</div>)}</details><p className="muted">Компромисс: {f.compromises.join(", ")}</p></article>)}</div></section>
  </main>;
}

createRoot(document.getElementById("root")!).render(<React.StrictMode><App /></React.StrictMode>);

