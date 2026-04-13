/**
 * ErrorBanner — dismissible error notification.
 *
 * @param {{ message: string, onDismiss: () => void }} props
 */
export default function ErrorBanner({ message, onDismiss }) {
  return (
    <div className="error-banner" role="alert">
      <span className="error-banner__icon" aria-hidden="true">⚠</span>
      <span className="error-banner__text">{message}</span>
      <button
        className="error-banner__dismiss"
        onClick={onDismiss}
        aria-label="Dismiss error"
        title="Dismiss"
      >
        ✕
      </button>
    </div>
  );
}
