import Foundation
import NetworkExtension

final class NearbyGuestNetwork {
    private var lease = NearbyHotspotLease()

    func cancel() {
        if let ssid = lease.cancel() {
            NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
        }
    }

    func join(_ payload: NearbyNetworkInvite, completion: @escaping (Bool) -> Void) {
        cancel()
        guard let ssid = payload.ssid, let passphrase = payload.passphrase else {
            completion(FlyNesNearbyBridge.sharedInstance.hasUsableIPv4())
            return
        }
        let current = lease.begin(ssid: ssid)
        let configuration = NEHotspotConfiguration(ssid: ssid, passphrase: passphrase, isWEP: false)
        configuration.joinOnce = true
        NEHotspotConfigurationManager.shared.apply(configuration) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                let applied = self.lease.complete(generation: current, ssid: ssid,
                                                  owned: error == nil)
                if let remove = applied.removeSSID {
                    NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: remove)
                }
                guard applied.accepted else { return }
                if let error {
                    let nsError = error as NSError
                    if nsError.domain != NEHotspotConfigurationErrorDomain ||
                        nsError.code != NEHotspotConfigurationError.alreadyAssociated.rawValue {
                        completion(false)
                        return
                    }
                }
                self.waitForRequestedWifi(ssid: ssid, generation: current,
                                          remaining: 40, completion: completion)
            }
        }
    }

    private func waitForRequestedWifi(ssid: String, generation: UInt64, remaining: Int,
                                      completion: @escaping (Bool) -> Void) {
        guard lease.isCurrent(generation) else { return }
        NEHotspotNetwork.fetchCurrent { [weak self] network in
            DispatchQueue.main.async {
                guard let self, self.lease.isCurrent(generation) else { return }
                let ready = NearbyWifiReadiness.ready(
                    expectedSSID: ssid,
                    currentSSID: network?.ssid,
                    hasWifiIPv4: FlyNesNearbyBridge.sharedInstance.hasUsableWifiIPv4()
                )
                if ready {
                    completion(true)
                } else if remaining == 0 {
                    self.cancel()
                    completion(false)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                        self?.waitForRequestedWifi(ssid: ssid, generation: generation,
                                                   remaining: remaining - 1, completion: completion)
                    }
                }
            }
        }
    }
}
