import { useEffect, useMemo } from 'react'
import { DeviceCard } from './DeviceCard.jsx'
import { getDeviceName } from '../utils/deviceHelpers.js'

// Unique key for dedup — falls back to hubName so offline devices without
// an iotInstanceName don't all collapse into a single "Unknown" entry.
function getDeviceKey(device) {
  if (!device) return 'Unknown'
  const name = getDeviceName(device)
  if (name !== 'Unknown') return name
  const hub = device.hubName ?? device.HubName ?? device.hub ?? device.Hub ?? null
  return hub ? `hub:${hub}` : 'Unknown'
}

const DEVICES_PER_PAGE = 6

export function DeviceGrid({
  devicesByHub,
  statusMap,
  arcStatusMap,
  onToast,
  onStatusUpdate,
  onSelectDevice,
  currentPage,
  onPageChange,
}) {
  // Sort devices by name for stable pagination across data refreshes,
  // and deduplicate in case the API returns the same device twice.
  const allDevices = useMemo(() => {
    const raw = devicesByHub || []
    const seen = new Set()
    const unique = []
    for (const d of raw) {
      const key = getDeviceKey(d)
      if (!seen.has(key)) {
        seen.add(key)
        unique.push(d)
      }
    }
    unique.sort((a, b) => getDeviceKey(a).localeCompare(getDeviceKey(b)))
    return unique
  }, [devicesByHub])
  const totalPages = Math.max(1, Math.ceil(allDevices.length / DEVICES_PER_PAGE))
  const validPage = Math.min(currentPage, totalPages)
  const startIdx = (validPage - 1) * DEVICES_PER_PAGE
  const endIdx = startIdx + DEVICES_PER_PAGE
  const paginatedDevices = allDevices.slice(startIdx, endIdx)

  useEffect(() => {
    if (currentPage !== validPage) onPageChange(validPage)
  }, [currentPage, validPage, onPageChange])

  const handlePrevPage = () => {
    if (validPage > 1) onPageChange(validPage - 1)
  }

  const handleNextPage = () => {
    if (validPage < totalPages) onPageChange(validPage + 1)
  }

  return (
    <div className="device-grid-container">
      <div className="devices-grid">
        {paginatedDevices.map(device => {
          const deviceKey = getDeviceKey(device)
          const dName = getDeviceName(device)
          let status = statusMap[dName] ?? statusMap[dName.toLowerCase()] ?? null
          if (!status) {
            const tryNames = [device.iotInstanceName, device.deviceName, device.DeviceName, device.device_name].filter(n => n && typeof n === 'string')
            for (const tryName of tryNames) {
              status = statusMap[tryName] ?? statusMap[tryName.toLowerCase()]
              if (status) break
            }
          }
          return (
            <div
              key={deviceKey}
              className="device-card-trigger"
            >
              <DeviceCard device={device} statusRecord={status} arcStatusData={arcStatusMap?.[dName] ?? arcStatusMap?.[dName.toLowerCase()] ?? arcStatusMap?.[dName.toUpperCase()] ?? null} onToast={onToast} onStatusUpdate={onStatusUpdate} onSelectDevice={onSelectDevice} />
            </div>
          )
        })}
      </div>

      {totalPages > 1 && (
        <div className="pagination-bar">
          <button className="pagination-btn pagination-prev" onClick={handlePrevPage} disabled={validPage === 1} aria-label="Previous page">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <polyline points="15 18 9 12 15 6" />
            </svg>
          </button>
          <div className="pagination-info">
            <span className="pagination-current">{validPage}</span>
            <span className="pagination-separator">/</span>
            <span className="pagination-total">{totalPages}</span>
          </div>
          <button className="pagination-btn pagination-next" onClick={handleNextPage} disabled={validPage === totalPages} aria-label="Next page">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <polyline points="9 18 15 12 9 6" />
            </svg>
          </button>
          <div className="pagination-dots">
            {Array.from({ length: totalPages }, (_, i) => i + 1).map(page => (
              <button key={page} className={`pagination-dot ${page === validPage ? 'active' : ''}`} onClick={() => onPageChange(page)} aria-label={`Go to page ${page}`} aria-current={page === validPage ? 'page' : undefined} />
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
