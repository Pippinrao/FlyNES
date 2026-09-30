import unittest
from harmony_contract_matchers import run_game_forwards_locator_and_autosave

class RunGameOpenMatcherTests(unittest.TestCase):
    def test_restores_head_independently_of_periodic_save_preference(self):
        self.assertTrue(run_game_forwards_locator_and_autosave(
            'await this.play.open(context, this.locator, true); '
            'if (!this.autosaveEnabled) this.play.history.intervalMs = 0;'))

    def test_accepts_formatted_call_and_guard(self):
        self.assertTrue(run_game_forwards_locator_and_autosave(
            'await this.play.open(\ncontext,\nthis.locator, true,\n); '
            'if ( !this.autosaveEnabled ) { this.play.history.intervalMs = 0; }'))

    def test_rejects_disabling_restore_when_periodic_save_is_disabled(self):
        self.assertFalse(run_game_forwards_locator_and_autosave(
            'this.play.open(context, this.locator, this.autosaveEnabled); '
            'if (!this.autosaveEnabled) this.play.history.intervalMs = 0;'))

    def test_rejects_unconditional_or_missing_interval_disable(self):
        for suffix in ['', 'this.play.history.intervalMs = 0;',
                       'if (this.autosaveEnabled) this.play.history.intervalMs = 0;']:
            self.assertFalse(run_game_forwards_locator_and_autosave(
                'this.play.open(context, this.locator, true); '+suffix))

    def test_rejects_wrong_receiver_locator_or_extra_argument(self):
        for call in ['this.player.open(context,this.locator,true)',
                     'this.play.open(context,this.pendingLocator,true)',
                     'this.play.open(context,this.locator,true,extra)']:
            self.assertFalse(run_game_forwards_locator_and_autosave(
                call+'; if (!this.autosaveEnabled) this.play.history.intervalMs=0;'))

if __name__ == '__main__': unittest.main()
