import { useLocation } from '@tanstack/react-router'
import { buttonClass } from '../components/ui/buttonClass'
import { Em } from '../components/ui/text'
import { useTitle } from '../lib/useTitle'
import { StatusScreen } from './StatusScreen'
import { MUTE } from '../lib/channels'

export default function NotFound() {
  useTitle('No pulse · Vitals')
  const path = useLocation({ select: (location) => location.pathname })
  return (
    <StatusScreen
      beats={[0.3, 0.28, 0.32]}
      stroke={MUTE}
      title={
        <>
          No pulse <Em className="text-mute">at this address.</Em>
        </>
      }
      code={['404', path, 'the link may be old']}
      actions={
        <>
          <a href="/" className={buttonClass('primary')}>
            Back to the chart
          </a>
          <a href="/releases" className={buttonClass('line')}>
            Chart notes
          </a>
        </>
      }
    />
  )
}
