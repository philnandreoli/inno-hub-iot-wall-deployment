import { useState, useEffect, useCallback, useRef } from 'react';
import { fetchInstances } from '../services/instanceApi';
import { useChat } from '../context/ChatContext';

/**
 * InstanceSelector — loads available AIO instances from the backend
 * and lets the user pick the active instance. Updates context
 * selectedInstanceId on selection.
 */
export default function InstanceSelector() {
  const { selectedInstanceId, setSelectedInstance } = useChat();
  const [instances, setInstances] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const cancelledRef = useRef(false);

  const loadInstances = useCallback(async () => {
    cancelledRef.current = false;
    setLoading(true);
    setError(null);
    try {
      const data = await fetchInstances();
      if (!cancelledRef.current) {
        setInstances(data.instances ?? []);
      }
    } catch (err) {
      if (!cancelledRef.current) {
        setError(err.message);
      }
    } finally {
      if (!cancelledRef.current) setLoading(false);
    }
  }, []);

  useEffect(() => {
    cancelledRef.current = false;
    loadInstances();
    return () => { cancelledRef.current = true; };
  }, [loadInstances]);

  const handleChange = (e) => {
    const value = e.target.value;
    setSelectedInstance(value || null);
  };

  return (
    <div className="instance-selector" aria-label="Instance selector">
      <h3 className="panel-title">IoT Operations Instance</h3>

      {loading && (
        <p className="instance-selector__status" role="status">Loading instances…</p>
      )}

      {error && (
        <div className="instance-selector__error" role="alert">
          <p>{error}</p>
          <button
            className="btn btn--ghost btn--sm instance-selector__retry"
            onClick={loadInstances}
            aria-label="Retry loading instances"
          >
            ↻ Retry
          </button>
        </div>
      )}

      {!loading && !error && instances.length === 0 && (
        <p className="instance-selector__status">No IoT Operations instances found</p>
      )}

      {!loading && !error && instances.length > 0 && (
        <>
          <label htmlFor="instance-select" className="sr-only">
            Select an IoT Operations instance
          </label>
          <select
            id="instance-select"
            className="instance-selector__select"
            value={selectedInstanceId ?? ''}
            onChange={handleChange}
            aria-label="Select an IoT Operations instance"
          >
            <option value="">-- Select instance --</option>
            {instances.map((inst) => (
              <option key={inst.name} value={inst.name}>
                {inst.name} ({inst.location})
              </option>
            ))}
          </select>
        </>
      )}
    </div>
  );
}
