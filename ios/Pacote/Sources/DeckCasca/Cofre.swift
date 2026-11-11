import Foundation

/// O que fica guardado depois de parear. O código de acesso é segredo: no iPhone mora no Keychain
/// (ios/App/CofreKeychain.swift) e nunca em arquivo, log ou tela.
public struct Pareado: Codable, Equatable, Sendable {
    public var codigoAcesso: String
    public var nomeMac: String
    /// O Mac no Bluetooth (identificador do rádio), para reconectar sem procurar. Nil se o pareamento foi pelo cabo.
    public var idBluetooth: String?

    public init(codigoAcesso: String, nomeMac: String, idBluetooth: String? = nil) {
        self.codigoAcesso = codigoAcesso
        self.nomeMac = nomeMac
        self.idBluetooth = idBluetooth
    }
}

public protocol Cofre: Sendable {
    func ler() -> Pareado?
    func gravar(_ pareado: Pareado)
    func apagar()
}

public extension Cofre {
    /// Guarda onde o Mac foi achado no Bluetooth, sem mexer no resto.
    func guardarBluetooth(_ id: String) {
        guard var atual = ler(), atual.idBluetooth != id else { return }
        atual.idBluetooth = id
        gravar(atual)
    }

    /// Rodízio: o Mac troca o código e o resto do pareamento continua igual.
    func trocarCodigo(_ novo: String) {
        guard var atual = ler() else { return }
        atual.codigoAcesso = novo
        gravar(atual)
    }
}

/// Para os testes e para o modo de prova.
public final class CofreEmMemoria: Cofre, @unchecked Sendable {
    private let trava = NSLock()
    private var guardado: Pareado?

    public init(_ inicial: Pareado? = nil) { guardado = inicial }

    public func ler() -> Pareado? { trava.lock(); defer { trava.unlock() }; return guardado }
    public func gravar(_ pareado: Pareado) { trava.lock(); guardado = pareado; trava.unlock() }
    public func apagar() { trava.lock(); guardado = nil; trava.unlock() }
}
