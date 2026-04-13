import { useState, useCallback } from 'react';
import { sendCommand } from '../services/commandApi';
import { useChat } from '../context/ChatContext';

const FAN_PRESETS = [
  { label: 'OFF (0)', value: 0 },
  { label: 'LOW (8000)', value: 8000 },
  { label: 'MED (16000)', value: 16000 },
  { label: 'HIGH (32000)', value: 32000 },
];

/**
 * CommandPanel — provides lamp and fan control buttons for the selected device.
 * Includes confirmation step and success/failure feedback.
 */
export default function CommandPanel() {
  const { selectedDeviceId } = useChat();
  const [fanSpeed, setFanSpeed] = useState('');
  const [sending, setSending] = useState(false);
  const [feedback, setFeedback] = useState(null); // { type: 'success'|'error', text }
  const [confirm, setConfirm] = useState(null); // { action, value, label }

  const clearFeedback = useCallback(() => setFeedback(null), []);

  /* ---------- confirm flow ---------------------------------------- */

  const requestConfirm = useCallback((action, value, label) => {
    setFeedback(null);
    setConfirm({ action, value, label });
  }, []);

  const cancelConfirm = useCallback(() => setConfirm(null), []);

  const executeCommand = useCallback(async () => {
    if (!confirm || !selectedDeviceId) return;
    const { action, value } = confirm;
    setConfirm(null);
    setSending(true);
    setFeedback(null);

    try {
      const result = await sendCommand(selectedDeviceId, action, value);
      setFeedback({
        type: result.success ? 'success' : 'error',
        text: result.message || 'Command sent.',
      });
    } catch (err) {
      setFeedback({ type: 'error', text: err.message });
    } finally {
      setSending(false);
    }
  }, [confirm, selectedDeviceId]);

  /* ---------- disabled state -------------------------------------- */

  if (!selectedDeviceId) {
    return (
      <div className="command-panel" aria-label="Device commands">
        <h3 className="panel-title">Commands</h3>
        <p className="command-panel__placeholder">Select a device to issue commands.</p>
      </div>
    );
  }

  const disabled = sending;

  /* ---------- render ---------------------------------------------- */

  return (
    <div className="command-panel" aria-label="Device commands">
      <h3 className="panel-title">Commands</h3>

      {/* Feedback banner */}
      {feedback && (
        <div
          className={`command-feedback command-feedback--${feedback.type}`}
          role="status"
        >
          <span>{feedback.text}</span>
          <button
            className="command-feedback__dismiss"
            onClick={clearFeedback}
            aria-label="Dismiss feedback"
          >
            ✕
          </button>
        </div>
      )}

      {/* Inline confirmation */}
      {confirm && (
        <div className="command-confirm" role="alertdialog" aria-label="Confirm command">
          <p className="command-confirm__text">
            Confirm: <strong>{confirm.label}</strong>?
          </p>
          <div className="command-confirm__actions">
            <button className="btn btn--primary btn--sm" onClick={executeCommand}>
              Yes, execute
            </button>
            <button className="btn btn--ghost btn--sm" onClick={cancelConfirm}>
              Cancel
            </button>
          </div>
        </div>
      )}

      {/* Lamp controls */}
      <fieldset className="command-group" disabled={disabled}>
        <legend className="command-group__legend">Lamp</legend>
        <div className="command-group__buttons">
          <button
            className="btn btn--success"
            onClick={() => requestConfirm('lamp', true, 'Turn Lamp ON')}
            aria-label="Turn lamp on"
          >
            💡 Lamp ON
          </button>
          <button
            className="btn btn--danger"
            onClick={() => requestConfirm('lamp', false, 'Turn Lamp OFF')}
            aria-label="Turn lamp off"
          >
            ⚫ Lamp OFF
          </button>
        </div>
      </fieldset>

      {/* Fan controls */}
      <fieldset className="command-group" disabled={disabled}>
        <legend className="command-group__legend">Fan</legend>

        {/* Preset buttons */}
        <div className="command-group__buttons command-group__buttons--wrap">
          {FAN_PRESETS.map((p) => (
            <button
              key={p.value}
              className="btn btn--outline btn--sm"
              onClick={() => requestConfirm('fan', p.value, `Set Fan to ${p.label}`)}
              aria-label={`Set fan speed to ${p.label}`}
            >
              {p.label}
            </button>
          ))}
        </div>

        {/* Custom speed input */}
        <div className="command-group__custom">
          <label htmlFor="fan-speed-input" className="sr-only">
            Custom fan speed (0–32000)
          </label>
          <input
            id="fan-speed-input"
            className="command-group__input"
            type="number"
            min={0}
            max={32000}
            step={100}
            placeholder="0–32000"
            value={fanSpeed}
            onChange={(e) => setFanSpeed(e.target.value)}
            aria-label="Custom fan speed"
          />
          <button
            className="btn btn--primary btn--sm"
            disabled={fanSpeed === '' || Number(fanSpeed) < 0 || Number(fanSpeed) > 32000}
            onClick={() =>
              requestConfirm('fan', Number(fanSpeed), `Set Fan Speed to ${fanSpeed}`)
            }
            aria-label="Set custom fan speed"
          >
            Set Fan Speed
          </button>
        </div>
      </fieldset>

      {sending && (
        <p className="command-panel__sending" role="status">
          Sending command…
        </p>
      )}
    </div>
  );
}
