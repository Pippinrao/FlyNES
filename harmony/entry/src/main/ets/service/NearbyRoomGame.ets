/** UI identity of the loaded nearby game survives page navigation. */
class NearbyRoomGame {
  canonicalId: string = '';
  title: string = '';
  select(canonicalId: string, title: string): void {
    this.canonicalId = canonicalId;
    this.title = title;
  }
  clear(): void { this.select('', ''); }
}
export const nearbyRoomGame: NearbyRoomGame = new NearbyRoomGame();
