import { useCallback, useEffect, useMemo, useRef, useState } from 'react'

const DAYS = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa']
const MONTHS = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
]

function getDaysInMonth(year, month) {
  return new Date(year, month + 1, 0).getDate()
}

function getFirstDayOfWeek(year, month) {
  return new Date(year, month, 1).getDay()
}

function pad(n) {
  return String(n).padStart(2, '0')
}

function formatDisplay(dateStr) {
  if (!dateStr) return ''
  const [y, m, d] = dateStr.split('-')
  return `${m}/${d}/${y}`
}

export function CalendarPicker({ value, onChange, label }) {
  const [open, setOpen] = useState(false)
  const ref = useRef(null)

  const today = useMemo(() => {
    const d = new Date()
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
  }, [])

  const [viewYear, viewMonth] = useMemo(() => {
    if (value) {
      const [y, m] = value.split('-').map(Number)
      return [y, m - 1]
    }
    const d = new Date()
    return [d.getFullYear(), d.getMonth()]
  }, [value])

  const [navYear, setNavYear] = useState(viewYear)
  const [navMonth, setNavMonth] = useState(viewMonth)

  // Sync nav when value changes externally
  useEffect(() => {
    setNavYear(viewYear)
    setNavMonth(viewMonth)
  }, [viewYear, viewMonth])

  // Close on outside click
  useEffect(() => {
    if (!open) return
    function handleClick(e) {
      if (ref.current && !ref.current.contains(e.target)) {
        setOpen(false)
      }
    }
    document.addEventListener('mousedown', handleClick)
    return () => document.removeEventListener('mousedown', handleClick)
  }, [open])

  const goPrev = useCallback(() => {
    setNavMonth(m => {
      if (m === 0) { setNavYear(y => y - 1); return 11 }
      return m - 1
    })
  }, [])

  const goNext = useCallback(() => {
    setNavMonth(m => {
      if (m === 11) { setNavYear(y => y + 1); return 0 }
      return m + 1
    })
  }, [])

  const selectDate = useCallback((day) => {
    const dateStr = `${navYear}-${pad(navMonth + 1)}-${pad(day)}`
    onChange(dateStr)
    setOpen(false)
  }, [navYear, navMonth, onChange])

  const clear = useCallback(() => {
    onChange('')
    setOpen(false)
  }, [onChange])

  const goToday = useCallback(() => {
    onChange(today)
    setOpen(false)
  }, [onChange, today])

  const daysInMonth = getDaysInMonth(navYear, navMonth)
  const firstDay = getFirstDayOfWeek(navYear, navMonth)

  // Build the 6-row grid (42 cells)
  const cells = useMemo(() => {
    const prevMonthDays = getDaysInMonth(navYear, navMonth - 1)
    const arr = []
    // Leading days from previous month
    for (let i = firstDay - 1; i >= 0; i--) {
      arr.push({ day: prevMonthDays - i, current: false })
    }
    // Current month
    for (let d = 1; d <= daysInMonth; d++) {
      arr.push({ day: d, current: true })
    }
    // Trailing days
    const remaining = 42 - arr.length
    for (let d = 1; d <= remaining; d++) {
      arr.push({ day: d, current: false })
    }
    return arr
  }, [navYear, navMonth, daysInMonth, firstDay])

  const selectedStr = value || ''

  return (
    <div className="cal-picker" ref={ref}>
      <button
        type="button"
        className="cal-picker-trigger"
        onClick={() => setOpen(o => !o)}
        aria-label={`${label}: ${value ? formatDisplay(value) : 'select date'}`}
      >
        <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <rect x="1" y="2.5" width="14" height="12" rx="2" />
          <line x1="1" y1="6.5" x2="15" y2="6.5" />
          <line x1="5" y1="1" x2="5" y2="4" />
          <line x1="11" y1="1" x2="11" y2="4" />
        </svg>
        <span className="cal-picker-value">{value ? formatDisplay(value) : label || 'Select'}</span>
      </button>
      {open && (
        <div className="cal-dropdown">
          <div className="cal-nav">
            <button type="button" className="cal-nav-btn" onClick={goPrev} aria-label="Previous month">‹</button>
            <span className="cal-nav-title">{MONTHS[navMonth]} {navYear}</span>
            <button type="button" className="cal-nav-btn" onClick={goNext} aria-label="Next month">›</button>
          </div>
          <div className="cal-grid">
            {DAYS.map(d => (
              <span key={d} className="cal-day-header">{d}</span>
            ))}
            {cells.map((cell, i) => {
              const dateStr = cell.current
                ? `${navYear}-${pad(navMonth + 1)}-${pad(cell.day)}`
                : ''
              const isSelected = cell.current && dateStr === selectedStr
              const isToday = cell.current && dateStr === today
              return (
                <button
                  key={i}
                  type="button"
                  className={[
                    'cal-day',
                    !cell.current && 'cal-day-outside',
                    isSelected && 'cal-day-selected',
                    isToday && !isSelected && 'cal-day-today',
                  ].filter(Boolean).join(' ')}
                  onClick={() => cell.current && selectDate(cell.day)}
                  disabled={!cell.current}
                  tabIndex={cell.current ? 0 : -1}
                >
                  {cell.day}
                </button>
              )
            })}
          </div>
          <div className="cal-footer">
            <button type="button" className="cal-footer-btn" onClick={clear}>Clear</button>
            <button type="button" className="cal-footer-btn" onClick={goToday}>Today</button>
          </div>
        </div>
      )}
    </div>
  )
}
