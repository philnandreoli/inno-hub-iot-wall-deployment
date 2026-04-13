import { useState, useEffect } from 'react';
import { fetchDeviceState } from '../services/deviceApi';
import { useChat } from '../context/ChatContext';

/**
 * DeviceStatePanel — displays the operational state of the selected device.
 */
export default function DeviceStatePanel() {
  const { selectedDeviceId } = useChat();
  const [state, setState] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    if (!selectedDeviceId) {
      setState(null);
      return;
    }

    let cancelled = false;

    async function load() {
      setLoading(true);
      setError(null);
      try {
        const data = await fetchDeviceState(selectedDeviceId);
        if (!cancelled) setState(data);
      } catch (err) {
        if (!cancelled) setError(err.message);
      } finally {
        if (!cancelled) setLoading(false);
      }
    }

    load();
    return () => { cancelled = true; };
  }, [selectedDeviceId]);

  /* -- Render states ------------------------------------------------ */

  if (!selectedDeviceId) {
    return (
      <div className="device-state-panel" aria-label="Device state">
        <h3 className="panel-title">Device State</h3>
        <p className="device-state-panel__placeholder">Select a device to view its state.</p>
      </div>
    );
  }

  if (loading) {
    return (
      <div className="device-state-panel" aria-label="Device state">
        <h3 className="panel-title">Device State</h3>
        <div className="device-state-panel__skeleton" role="status">
          <span className="sr-only">Loading device state…</span>
          {[1, 2, 3, 4].map((i) => (
            <div key={i} className="skeleton-line" />
          ))}
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="device-state-panel" aria-label="Device state">
        <h3 className="panel-title">Device State</h3>
        <p className="device-state-panel__error" role="alert">{error}</p>
      </div>
    );
  }

  if (!state) return null;

  return (
    <div className="device-state-panel" aria-label="Device state">
      <h3 className="panel-title">Device State</h3>
      <dl className="device-state-panel__list">
        {/* Online status */}
        <div className="state-row">
          <dt>Status</dt>
          <dd>
            <span
              className={`status-dot ${state.online ? 'status-dot--online' : 'status-dot--offline'}`}
              aria-hidden="true"
            />
            {state.online ? 'Online' : 'Offline'}
          </dd>
        </div>

        {/* Lamp */}
        <div className="state-row">
          <dt>Lamp</dt>
          <dd>
            <span aria-hidden="true">{state.lamp ? '💡' : '⚫'}</span>{' '}
            {state.lamp != null ? (state.lamp ? 'ON' : 'OFF') : 'State unavailable'}
          </dd>
        </div>

        {/* Fan */}
        <div className="state-row">
          <dt>Fan Speed</dt>
          <dd>
            {state.fan != null ? (
              <>
                <span className="fan-speed-value">{state.fan}</span>
                <div className="fan-speed-bar" aria-label={`Fan speed ${state.fan} of 32000`}>
                  <div
                    className="fan-speed-bar__fill"
                    style={{ width: `${Math.min((state.fan / 32000) * 100, 100)}%` }}
                  />
                </div>
              </>
            ) : (
              'State unavailable'
            )}
          </dd>
        </div>

        {/* Temperature */}
        <div className="state-row">
          <dt>Temperature</dt>
          <dd>
            {state.temperature != null ? `${state.temperature} °C` : 'State unavailable'}
          </dd>
        </div>

        {/* Vibration */}
        <div className="state-row">
          <dt>Vibration</dt>
          <dd>
            {state.vibration != null ? state.vibration : 'State unavailable'}
          </dd>
        </div>

        {/* Error code */}
        {state.error_code && (
          <div className="state-row state-row--error">
            <dt>Error Code</dt>
            <dd className="state-error-code">{state.error_code}</dd>
          </div>
        )}

        {/* Last updated */}
        <div className="state-row">
          <dt>Last Updated</dt>
          <dd>
            {state.last_updated
              ? new Date(state.last_updated).toLocaleString()
              : 'State unavailable'}
          </dd>
        </div>
      </dl>
    </div>
  );
}
