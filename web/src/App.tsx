import { useCallback, useEffect, useState } from "react";
import { applyMitigation, createSession, generateFutures, getForecast, simulateFuture, updateTravelDna } from "./api";
import type { DreamInput, Forecast, Future, Job, PlanningSession, SimulationRequest, TravelDnaElementInput } from "./api";
import { DreamForm } from "./components/DreamForm";
import { ForecastPanel } from "./components/ForecastPanel";
import { FuturesView } from "./components/FuturesView";
import { SimulatorPanel } from "./components/SimulatorPanel";
import { TravelDnaPanel } from "./components/TravelDnaPanel";
import { TripPlan } from "./components/TripPlan";
import { ApiProblem } from "./generated/client";

export function App() {
  const [session, setSession] = useState<PlanningSession | null>(null);
  const [submittedInput, setSubmittedInput] = useState<DreamInput | null>(null);
  const [futures, setFutures] = useState<Future[]>([]);
  const [diversityNote, setDiversityNote] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isGenerating, setIsGenerating] = useState(false);
  const [isUpdatingDna, setIsUpdatingDna] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [dnaError, setDnaError] = useState<string | null>(null);
  const [chosen, setChosen] = useState<Future | null>(null);
  const [forecast, setForecast] = useState<Forecast | null>(null);
  const [isForecasting, setIsForecasting] = useState(false);
  const [forecastError, setForecastError] = useState<string | null>(null);

  const handleDream = async (input: DreamInput) => {
    setIsSubmitting(true);
    setError(null);
    setDnaError(null);
    setSession(null);
    setSubmittedInput(null);
    setFutures([]);
    setDiversityNote(null);
    setChosen(null);
    setForecast(null);

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

  const handleUpdateDna = async (elements: TravelDnaElementInput[]) => {
    if (!session) return;
    setIsUpdatingDna(true);
    setDnaError(null);

    try {
      const travelDna = await updateTravelDna(session.id, elements);
      setSession((current) => current ? { ...current, travel_dna: travelDna } : current);
    } catch (caught) {
      setDnaError(errorMessage(caught));
      throw caught;
    } finally {
      setIsUpdatingDna(false);
    }
  };

  // The forecast belongs to a specific version of a Future, so it is refetched whenever the chosen version
  // changes — a simulation produces a new version, and carrying the old risks across would be a lie.
  useEffect(() => {
    if (!chosen) return;

    let cancelled = false;
    setIsForecasting(true);
    setForecastError(null);

    getForecast(chosen.id)
      .then((result) => { if (!cancelled) setForecast(result); })
      .catch((caught) => { if (!cancelled) { setForecast(null); setForecastError(errorMessage(caught)); } })
      .finally(() => { if (!cancelled) setIsForecasting(false); });

    return () => { cancelled = true; };
  }, [chosen]);

  const handleSimulate = useCallback(
    (request: SimulationRequest): Promise<Job> => simulateFuture(chosen!.id, request),
    [chosen],
  );

  // A simulation never edits a Future; it produces a new version. The chosen version moves forward, and the
  // list keeps the original so the user can still see what they came from.
  const handleSimulated = useCallback((next: Future) => setChosen(next), []);

  const handleFixRisk = useCallback(async (riskId: string, mitigationId: string) => {
    if (!chosen) return;
    const job = await applyMitigation(chosen.id, riskId, mitigationId);
    const mitigated = job.result?.future;
    if (job.status !== "succeeded" || !mitigated) {
      throw new ApiProblem(502, { title: "Митигация не применена", status: 502 });
    }
    setChosen(mitigated);
  }, [chosen]);

  const handleGenerate = async () => {
    if (!session) return;
    setIsGenerating(true);
    setError(null);

    try {
      const result = await generateFutures(session.id);
      setFutures(result.futures);
      setDiversityNote(result.diversity_note ?? null);
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

            <TravelDnaPanel
              dna={session.travel_dna}
              isSaving={isUpdatingDna}
              error={dnaError}
              onSave={handleUpdateDna}
            />

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
        <FuturesView
          futures={futures}
          diversityNote={diversityNote}
          chosenId={chosen?.lineage_id ?? null}
          onChoose={setChosen}
        />
      )}

      {chosen && (
        <>
          <SimulatorPanel future={chosen} onSimulate={handleSimulate} onApplyResult={handleSimulated} />
          <ForecastPanel
            forecast={forecast}
            isLoading={isForecasting}
            error={forecastError}
            onFixRisk={handleFixRisk}
          />
          <TripPlan future={chosen} />
        </>
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
