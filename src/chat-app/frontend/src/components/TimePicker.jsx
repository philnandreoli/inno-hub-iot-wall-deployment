import { useCallback, useEffect, useRef, useState } from 'react'

function pad(n) {
  return String(n).padStart(2, '0')
}

function parse24(value) {
  if (!value) return { h: 12, m: 0, period: 'AM' }
  const [hStr, mStr] = value.split(':')
  let h = parseInt(hStr, 10) || 0
  const m = parseInt(mStr, 10) || 0
  const period = h >= 12 ? 'PM' : 'AM'
  if (h === 0) h = 12
  else if (h > 12) h -= 12
  return { h, m, period }
}

function to24(h, m, period) {
  let h24 = h
  if (period === 'AM' && h === 12) h24 = 0
  else if (period === 'PM' && h !== 12) h24 = h + 12
  return `${pad(h24)}:${pad(m)}`
}

const HOURS = Array.from({ length: 12 }, (_, i) => i + 1)
const MINUTES = Array.from({ length: 12 }, (_, i) => i * 5)

export function TimePicker({ value, onChange, disabled }) {
  const [open, setOpen] = useState(false)
  const ref = useRef(null)
  const hourRef = useRef(null)
  const minRef = useRef(null)

  const { h, m, period } = parse24(value)

  // Close on outside click
  useEffect(() => {
    if (!open) return
    function handleClick(e) {
      if (ref.current && !ref.current.contains(e.target)) setOpen(false)
    }
    document.addEventListener('mousedown', handleClick)
    return () => document.removeEventListener('mousedown', handleClick)
  }, [open])

  // Scroll selected into view on open
  useEffect(() => {
    if (!open) return
    requestAnimationFrame(() => {
      hourRef.current?.querySelector('.tp-option.selected')?.scrollIntoView({ block: 'center' })
      minRef.current?.querySelector('.tp-option.selected')?.scrollIntoView({ block: 'center' })
    })
  }, [open])

  const emit = useCallback((newH, newM, newPeriod) => {
    onChange(to24(newH, newM, newPeriod))
  }, [onChange])

  const display = value
    ? `${h}:${pad(m)} ${period}`
    : '--:--'

  return (
    <div className="tp-picker" ref={ref}>
      <button
        type="button"
        className="tp-trigger"
        onClick={() => !disabled && setOpen(o => !o)}
        disabled={disabled}
        aria-label={`Time: ${display}`}
      >
        <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <circle cx="8" cy="8" r="7" />
          <polyline points="8,3.5 8,8 11,10" />
        </svg>
        <span className="tp-value">{display}</span>
      </button>
      {open && (
        <div className="tp-dropdown">
          <div className="tp-columns">
            <div className="tp-column" ref={hourRef}>
              <div className="tp-col-header">Hr</div>
              <div className="tp-scroll">
                {HOURS.map(hr => (
                  <button
                    key={hr}
                    type="button"
                    className={`tp-option ${hr === h ? 'selected' : ''}`}
                    onClick={() => emit(hr, m, period)}
                  >
                    {hr}
                  </button>
                ))}
              </div>
            </div>
            <div className="tp-column" ref={minRef}>
              <div className="tp-col-header">Min</div>
              <div className="tp-scroll">
                {MINUTES.map(min => (
                  <button
                    key={min}
                    type="button"
                    className={`tp-option ${min === m ? 'selected' : ''}`}
                    onClick={() => emit(h, min, period)}
                  >
                    {pad(min)}
                  </button>
                ))}
              </div>
            </div>
            <div className="tp-column tp-period-col">
              <div className="tp-col-header">&nbsp;</div>
              <div className="tp-scroll">
                <button
                  type="button"
                  className={`tp-option ${period === 'AM' ? 'selected' : ''}`}
                  onClick={() => emit(h, m, 'AM')}
                >
                  AM
                </button>
                <button
                  type="button"
                  className={`tp-option ${period === 'PM' ? 'selected' : ''}`}
                  onClick={() => emit(h, m, 'PM')}
                >
                  PM
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
