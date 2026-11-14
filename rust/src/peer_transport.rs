use snow::{Builder, HandshakeState, TransportState};
use std::time::{Duration, Instant};
use zeroize::Zeroizing;

const PROTOCOL: &str = "Noise_XX_25519_ChaChaPoly_SHA256";
const CONTEXT: &[u8] = b"com.blue.qingniao/peer-transport/v1";
const MAX_HANDSHAKE: usize = 1024;
pub const MAX_PLAINTEXT: usize = 32 * 1024;
const MAX_MESSAGES: u64 = 1 << 20;

pub struct PeerHandshake {
    state: Option<HandshakeState>,
    expected_peer: [u8; 32],
    started: Instant,
}

impl PeerHandshake {
    // The caller must obtain the peer key through an authenticated pairing channel.
    pub fn new(local_secret: Zeroizing<[u8; 32]>, expected_peer: [u8; 32], initiator: bool) -> Result<Self, String> {
        if expected_peer == [0; 32] { return Err("Invalid peer identity".into()); }
        let parameters = PROTOCOL.parse().map_err(|_| "Invalid protocol")?;
        let builder = Builder::new(parameters).prologue(CONTEXT).map_err(|_| "Invalid context")?
            .local_private_key(local_secret.as_ref()).map_err(|_| "Invalid local identity")?;
        let state = if initiator { builder.build_initiator() } else { builder.build_responder() }
            .map_err(|_| "Unable to initialize handshake")?;
        Ok(Self { state: Some(state), expected_peer, started: Instant::now() })
    }

    fn take_state(&mut self) -> Result<HandshakeState, String> {
        if self.started.elapsed() > Duration::from_secs(30) {
            self.state = None;
            return Err("Handshake expired".into());
        }
        self.state.take().ok_or_else(|| "Handshake closed".into())
    }

    pub fn write(&mut self) -> Result<Vec<u8>, String> {
        let mut state = self.take_state()?;
        let mut frame = vec![0; MAX_HANDSHAKE];
        let length = state.write_message(&[], &mut frame).map_err(|_| "Handshake write failed")?;
        frame.truncate(length);
        self.state = Some(state);
        Ok(frame)
    }

    pub fn read(&mut self, frame: &[u8]) -> Result<(), String> {
        let mut state = self.take_state()?;
        if frame.is_empty() || frame.len() > MAX_HANDSHAKE { return Err("Invalid handshake frame size".into()); }
        let mut plaintext = Zeroizing::new(vec![0; MAX_HANDSHAKE]);
        let length = state.read_message(frame, &mut plaintext).map_err(|_| "Handshake authentication failed")?;
        if length != 0 { return Err("Handshake payload is forbidden".into()); }
        if let Some(remote) = state.get_remote_static() {
            if remote != self.expected_peer { return Err("Peer identity mismatch".into()); }
        }
        self.state = Some(state);
        Ok(())
    }

    pub fn finish(mut self) -> Result<PeerTransport, String> {
        let state = self.take_state()?;
        if !state.is_handshake_finished() || state.get_remote_static() != Some(self.expected_peer.as_slice()) {
            return Err("Peer is not authenticated".into());
        }
        let transport = state.into_transport_mode().map_err(|_| "Handshake incomplete")?;
        Ok(PeerTransport { state: Some(transport), started: Instant::now(), sent: 0, received: 0 })
    }
}

pub struct PeerTransport {
    state: Option<TransportState>,
    started: Instant,
    sent: u64,
    received: u64,
}

impl PeerTransport {
    fn take_state(&mut self) -> Result<TransportState, String> {
        if self.started.elapsed() > Duration::from_secs(3600) || self.sent >= MAX_MESSAGES || self.received >= MAX_MESSAGES {
            self.state = None;
            return Err("Session requires a fresh handshake".into());
        }
        self.state.take().ok_or_else(|| "Session closed".into())
    }

    pub fn encrypt(&mut self, plaintext: &[u8]) -> Result<Vec<u8>, String> {
        if plaintext.len() > MAX_PLAINTEXT { return Err("Message exceeds frame limit".into()); }
        let mut state = self.take_state()?;
        let mut frame = vec![0; plaintext.len() + 16];
        let length = state.write_message(plaintext, &mut frame).map_err(|_| "Encryption failed")?;
        frame.truncate(length);
        self.sent += 1;
        self.state = Some(state);
        Ok(frame)
    }

    // Ordered reliable delivery is required; authentication failures terminate the session.
    pub fn decrypt(&mut self, frame: &[u8]) -> Result<Zeroizing<Vec<u8>>, String> {
        let mut state = self.take_state()?;
        if !(16..=MAX_PLAINTEXT + 16).contains(&frame.len()) { return Err("Invalid encrypted frame size".into()); }
        let mut plaintext = Zeroizing::new(vec![0; frame.len() - 16]);
        let length = state.read_message(frame, &mut plaintext).map_err(|_| "Message authentication failed")?;
        plaintext.truncate(length);
        self.received += 1;
        self.state = Some(state);
        Ok(plaintext)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn identities() -> (snow::Keypair, snow::Keypair) {
        let builder = Builder::new(PROTOCOL.parse().unwrap());
        (builder.generate_keypair().unwrap(), builder.generate_keypair().unwrap())
    }
    fn pair() -> (PeerTransport, PeerTransport) {
        let (a, b) = identities();
        let mut initiator = PeerHandshake::new(Zeroizing::new(a.private.as_slice().try_into().unwrap()), b.public.as_slice().try_into().unwrap(), true).unwrap();
        let mut responder = PeerHandshake::new(Zeroizing::new(b.private.as_slice().try_into().unwrap()), a.public.as_slice().try_into().unwrap(), false).unwrap();
        responder.read(&initiator.write().unwrap()).unwrap();
        initiator.read(&responder.write().unwrap()).unwrap();
        responder.read(&initiator.write().unwrap()).unwrap();
        (initiator.finish().unwrap(), responder.finish().unwrap())
    }
    #[test]
    fn authenticates_and_encrypts_both_directions() {
        let (mut a, mut b) = pair();
        assert_eq!(*b.decrypt(&a.encrypt("短信🌿".as_bytes()).unwrap()).unwrap(), "短信🌿".as_bytes());
        assert_eq!(*a.decrypt(&b.encrypt(b"reply").unwrap()).unwrap(), b"reply");
    }
    #[test]
    fn rejects_replay_and_closes_connection() {
        let (mut a, mut b) = pair();
        let frame = a.encrypt(b"secret").unwrap();
        assert!(b.decrypt(&frame).is_ok());
        assert!(b.decrypt(&frame).is_err());
        assert!(b.decrypt(&a.encrypt(b"later").unwrap()).is_err());
    }
    #[test]
    fn rejects_tampering_and_cross_session_ciphertext() {
        let (mut a, mut b) = pair();
        let mut frame = a.encrypt(b"secret").unwrap();
        frame[0] ^= 1;
        assert!(b.decrypt(&frame).is_err());
        let (_, mut other) = pair();
        assert!(other.decrypt(&a.encrypt(b"secret").unwrap()).is_err());
    }
    #[test]
    fn requires_pinned_peer_and_completed_handshake() {
        let (a, b) = identities();
        let (impostor, _) = identities();
        let mut initiator = PeerHandshake::new(Zeroizing::new(a.private.as_slice().try_into().unwrap()), impostor.public.as_slice().try_into().unwrap(), true).unwrap();
        let mut responder = PeerHandshake::new(Zeroizing::new(b.private.as_slice().try_into().unwrap()), a.public.as_slice().try_into().unwrap(), false).unwrap();
        responder.read(&initiator.write().unwrap()).unwrap();
        assert!(initiator.read(&responder.write().unwrap()).is_err());
        assert!(initiator.finish().is_err());
        assert!(responder.finish().is_err());
    }
    #[test]
    fn enforces_frame_bounds() {
        let (mut a, mut b) = pair();
        assert!(a.encrypt(&vec![0; MAX_PLAINTEXT + 1]).is_err());
        let frame = a.encrypt(&vec![7; MAX_PLAINTEXT]).unwrap();
        assert_eq!(b.decrypt(&frame).unwrap().len(), MAX_PLAINTEXT);
        assert!(b.decrypt(&[]).is_err());
    }
}
