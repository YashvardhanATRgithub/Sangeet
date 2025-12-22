import Foundation
import Combine

@MainActor
protocol ViewModel: ObservableObject {
    var isLoading: Bool { get }
    var errorMessage: String? { get }
}

open class BaseViewModel: ViewModel {
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    
    public init() {}
}
