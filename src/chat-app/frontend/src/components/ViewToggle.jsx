/**
 * A pill-shaped slider toggle to switch between Grid and Map views.
 */
export function ViewToggle({ view, onToggle }) {
  const isMap = view === 'map'

  return (
    <div className="view-toggle-wrapper">
      <button
        type="button"
        className={`view-toggle-option ${!isMap ? 'active' : ''}`}
        onClick={() => onToggle('grid')}
        aria-pressed={!isMap}
      >
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <rect x="3" y="3" width="7" height="7" />
          <rect x="14" y="3" width="7" height="7" />
          <rect x="3" y="14" width="7" height="7" />
          <rect x="14" y="14" width="7" height="7" />
        </svg>
        Grid
      </button>

      <div className="view-toggle-track" onClick={() => onToggle(isMap ? 'grid' : 'map')} role="switch" aria-checked={isMap} tabIndex={0} onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onToggle(isMap ? 'grid' : 'map') } }}>
        <span className={`view-toggle-thumb ${isMap ? 'right' : 'left'}`} />
      </div>

      <button
        type="button"
        className={`view-toggle-option ${isMap ? 'active' : ''}`}
        onClick={() => onToggle('map')}
        aria-pressed={isMap}
      >
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <polygon points="1 6 1 22 8 18 16 22 23 18 23 2 16 6 8 2 1 6" />
          <line x1="8" y1="2" x2="8" y2="18" />
          <line x1="16" y1="6" x2="16" y2="22" />
        </svg>
        Map
      </button>
    </div>
  )
}
