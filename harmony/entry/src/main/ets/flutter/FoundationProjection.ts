export interface FoundationCatalogSource {
  canonicalId: string;
  titleEn: string;
  titleZhHans: string;
  builtin: boolean;
  sourceUuidHex: string;
  sourceRelativePath: string;
}

export interface FoundationGame {
  canonicalId: string;
  titleEn: string;
  titleZhHans: string;
  available: boolean;
  unavailableReason: string;
  coverPath: string;
}

export interface FoundationSnapshot {
  generation: number;
  games: FoundationGame[];
}

export function isFlutterFoundationRoute(page: string | undefined, debug: boolean): boolean {
  return debug && page === 'flutter_foundation';
}

// Source-locator availability mirrors GameCenter.canOpenSelected; it does not
// promise that the separate Flutter launch/resume bridge is implemented.
export function foundationSnapshot(rows: FoundationCatalogSource[], generation: number): FoundationSnapshot {
  const games: FoundationGame[] = [];
  for (let index = 0; index < rows.length; index++) {
    const row = rows[index];
    const available = row.builtin || (row.sourceUuidHex.length === 32 && row.sourceRelativePath.length > 0);
    games.push({ canonicalId: row.canonicalId, titleEn: row.titleEn, titleZhHans: row.titleZhHans,
      available: available, unavailableReason: available ? '' : '游戏来源不可用', coverPath: '' });
  }
  return { generation: generation, games: games };
}
