import { useState } from "react";
import { createSession, generateFutures } from "./api";
import type { DreamInput, Future, PlanningSession } from "./api";
import { DreamForm } from "./components/DreamForm";
import { ApiProblem } from "./generated/client";

export function App() {
  const [session, setSession] = useState<PlanningSession | null>(null);
  const [submittedInput, setSubmittedInput] = useState<DreamInput | null>(null);
  const [futures, setFutures] = useState<Future[]>([]);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isGenerating, setIsGenerating] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleDream = async (input: DreamInput) => {
    setIsSubmitting(true);
    setError(null);
    setSession(null);
    setSubmittedInput(null);
    setFutures([]);

    try {
      const created = await createSession(input);
      setSubmittedInput(input);
      setSession(created);
    } catch (caught) {
      setError(errorMessage(caught));
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleGenerate = async () => {
    if (!session) return;
    setIsGenerating(true);
    setError(null);

    try {
      const result = await generateFutures(session.id);
      setFutures(result.futures);
    } catch (caught) {
      setError(errorMessage(caught));
    } finally {
      setIsGenerating(false);
    }
  };

  return (
    <main>
      <header className="hero">
        <div className="hero-topline">
          <span className="eyebrow">ELSEWHERE</span>
          <span className="step-marker">Шаг 1 из 6 · Мечта</span>
        </div>
        <h1>Сначала — какой должна быть поездка?</h1>
        <p className="hero-copy">
          Не выбирайте отель из сотни одинаковых карточек. Опишите будущее, в котором хотите оказаться,
          а мы сначала покажем, как вас поняли.
        </p>
      </header>

      <section className="dream-shell" aria-labelledby="dream-form-title">
        <div className="section-heading">
          <div>
            <span className="section-index">01</span>
            <h2 id="dream-form-title">Расскажите о поездке</h2>
          </div>
          <p>Никаких скрытых предположений: обязательные параметры спрашиваем прямо.</p>
        </div>

        {error && (
          <div className="request-error" role="alert">
            <strong>Не удалось создать планирование</strong>
            <span>{error}</span>
          </div>
        )}

        <DreamForm isSubmitting={isSubmitting} onSubmit={handleDream} />
      </section>

      {session && submittedInput && (
        <section className="session-result" aria-labelledby="session-result-title">
          <div className="success-mark" aria-hidden="true">✓</div>
          <div className="session-result__content">
            <span className="result-kicker">Черновик создан</span>
            <h2 id="session-result-title">Вот что мы услышали</h2>
            <p>
              Travel DNA пока не окончательный: на следующем шаге можно исправить каждое предположение.
            </p>

            <dl className="session-facts">
              <div><dt>Откуда</dt><dd>{submittedInput.origin}</dd></div>
              <div>
                <dt>Окно поездки</dt>
                <dd>{formatDate(submittedInput.date_window.earliest)} — {formatDate(submittedInput.date_window.latest)}</dd>
              </div>
              <div>
                <dt>Длительность</dt>
                <dd>{submittedInput.date_window.nights_min}–{submittedInput.date_window.nights_max} ночей</dd>
              </div>
              <div><dt>Путешественники</dt><dd>{submittedInput.party.adults}</dd></div>
            </dl>

            <div className="dna-preview" aria-label="Черновик Travel DNA">
              {session.travel_dna.elements.slice(0, 8).map((element) => (
                <span key={element.dimension}>{element.dimension} · {element.provenance}</span>
              ))}
            </div>

            {session.clarifications.length > 0 && (
              <p className="clarification-note">
                Есть уточнения: {session.clarifications.length}. Ответим на них перед поиском.
              </p>
            )}

            <button
              className="secondary-action"
              type="button"
              disabled={isGenerating}
              onClick={handleGenerate}
            >
              {isGenerating ? "Собираем варианты…" : "Продолжить к вариантам"}
            </button>
          </div>
        </section>
      )}

      {futures.length > 0 && (
        <section aria-labelledby="futures-title">
          <h2 id="futures-title">Возможные будущие</h2>
          <div className="grid">
            {futures.map((future) => (
              <article key={future.id}>
                <div className="score">{Math.round(future.match.score * 100)}%</div>
                <h3>{future.destination.name}</h3>
                <p>{future.why_this_exists}</p>
                <strong>{formatMoney(future.price.total)}</strong>
                <small>Перелёт оценён по рынку; проживание и наземные расходы смоделированы.</small>
              </article>
            ))}
          </div>
        </section>
      )}
    </main>
  );
}

function errorMessage(error: unknown) {
  if (error instanceof ApiProblem) return error.message;
  if (error instanceof TypeError) return "Сервис недоступен. Проверьте подключение и попробуйте ещё раз.";
  if (error instanceof Error) return error.message;
  return "Произошла неизвестная ошибка. Попробуйте ещё раз.";
}

function formatDate(date: string) {
  return new Intl.DateTimeFormat("ru-RU", { day: "numeric", month: "short", year: "numeric" })
    .format(new Date(`${date}T00:00:00`));
}

function formatMoney(money: { amount_minor: number; currency: string }) {
  return new Intl.NumberFormat("ru-RU", { style: "currency", currency: money.currency, maximumFractionDigits: 0 })
    .format(money.amount_minor / 100);
}
