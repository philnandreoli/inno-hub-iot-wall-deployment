/**
 * LoadingIndicator — animated dots displayed while a request is in-flight.
 */
export default function LoadingIndicator() {
  return (
    <div className="loading-indicator" role="status" aria-label="Loading response">
      <span className="loading-indicator__dot" />
      <span className="loading-indicator__dot" />
      <span className="loading-indicator__dot" />
      <span className="sr-only">Loading…</span>
    </div>
  );
}
