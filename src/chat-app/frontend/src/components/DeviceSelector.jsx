import { useState, useEffect } from 'react';
import { fetchDevices } from '../services/deviceApi';
import { useChat } from '../context/ChatContext';

/**
 * DeviceSelector — loads device list from the backend and lets the user
 * pick the active device. Updates context selectedDeviceId on selection.
 */
export default function DeviceSelector() {
  const { selectedDeviceId, setSelectedDevice } = useChat();
  const [devices, setDevices] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    let cancelled = false;

    async function load() {
      setLoading(true);
      setError(null);
      try {
        const data = await fetchDevices();
        if (!cancelled) {
          setDevices(data.devices ?? []);
        }
      } catch (err) {
        if (!cancelled) {
          setError(err.message);
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    }

    load();
    return () => { cancelled = true; };
  }, []);

  const handleChange = (e) => {
    const value = e.target.value;
    setSelectedDevice(value || null);
  };

  return (
    <div className="device-selector" aria-label="Device selector">
      <h3 className="panel-title">Devices</h3>

      {loading && (
        <p className="device-selector__status" role="status">Loading devices…</p>
      )}

      {error && (
        <p className="device-selector__error" role="alert">
          {error}
        </p>
      )}

      {!loading && !error && devices.length === 0 && (
        <p className="device-selector__status">No devices available</p>
      )}

      {!loading && !error && devices.length > 0 && (
        <>
          <label htmlFor="device-select" className="sr-only">
            Select a device
          </label>
          <select
            id="device-select"
            className="device-selector__select"
            value={selectedDeviceId ?? ''}
            onChange={handleChange}
            aria-label="Select a device"
          >
            <option value="">-- Select device --</option>
            {devices.map((d) => (
              <option key={d} value={d}>
                {d}
              </option>
            ))}
          </select>
        </>
      )}
    </div>
  );
}
