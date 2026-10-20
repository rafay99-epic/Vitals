import { SUPPORT_EMAIL } from '../lib/links'
import { buttonClass } from '../components/ui/buttonClass'
import { Em } from '../components/ui/text'
import { useTitle } from '../lib/useTitle'
import { StatusScreen } from './StatusScreen'
import { ALARM_HIGH } from '../lib/channels'

export default function ErrorScreen() {
  useTitle('Something stopped · Vitals')
  return (
    <StatusScreen
      beats={[0.28, 0.3, 0.9, 0.15, 0.75, 0.1]}
      stroke={ALARM_HIGH}
      title={
        <>
          Something <Em className="text-mute">stopped.</Em>
        </>
      }
      message="This page hit an error and could not finish loading. Your Mac is fine. Reloading usually clears it."
      code={['error · this page', 'nothing was sent anywhere']}
      actions={
        <>
          <button type="button" onClick={() => window.location.reload()} className={`${buttonClass('primary')} cursor-pointer border-0`}>
            Reload
          </button>
          <a href={`mailto:${SUPPORT_EMAIL}`} className={buttonClass('line')}>
            Report a problem
          </a>
        </>
      }
    />
  )
}
