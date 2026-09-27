package com.flynes.emu;

import org.junit.Test;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public final class NearbyPeerGameAttemptTest {
    @Test public void sameGameKeyRetriesForANewPeerConfiguration() {
        NearbyPeerGameAttempt attempt = new NearbyPeerGameAttempt();
        assertTrue(attempt.shouldAttempt(NearbyMvpSession.CONFIGURING, 0, "game", "hash-one"));
        assertFalse(attempt.shouldAttempt(NearbyMvpSession.CONFIGURING, 0, "game", "hash-one"));
        assertTrue(attempt.shouldAttempt(NearbyMvpSession.CONFIGURING, 0, "game", "hash-two"));
        assertFalse(attempt.shouldAttempt(NearbyMvpSession.CONFIGURING, 0, "game", "hash-two"));
        assertTrue(attempt.shouldAttempt(NearbyMvpSession.CONFIGURING, 1, "game", "hash-three"));
    }

    @Test public void returningToLobbyAllowsTheSameGameAgain() {
        NearbyPeerGameAttempt attempt = new NearbyPeerGameAttempt();
        assertTrue(attempt.shouldAttempt(NearbyMvpSession.CONFIGURING, 0, "game", "hash-one"));
        assertFalse(attempt.shouldAttempt(NearbyMvpSession.LOBBY, 0, "", ""));
        assertTrue(attempt.shouldAttempt(NearbyMvpSession.CONFIGURING, 0, "game", "hash-one"));
    }

    @Test public void openingAnAlreadyConfiguredLobbyDoesNotReloadTheRom() {
        NearbyPeerGameAttempt attempt = new NearbyPeerGameAttempt();
        assertFalse(attempt.shouldAttempt(NearbyMvpSession.CONFIGURING, 1, "game", "hash-one"));
        assertTrue(attempt.shouldAttempt(NearbyMvpSession.CONFIGURING, 1, "game", "hash-two"));
    }

    @Test public void skippedLobbyStateStillRetriesTheSameGameInANewRound() {
        NearbyPeerGameAttempt attempt = new NearbyPeerGameAttempt();
        assertTrue(attempt.shouldAttempt(NearbyMvpSession.CONFIGURING, 0, "game", "hash-one"));
        assertFalse(attempt.shouldAttempt(NearbyMvpSession.CONFIGURING, 1, "game", "hash-one"));
        assertTrue(attempt.shouldAttempt(NearbyMvpSession.CONFIGURING, 0, "game", "hash-one"));
    }
}
