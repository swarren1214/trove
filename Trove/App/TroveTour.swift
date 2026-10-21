import SwiftUI

/// Trove's stops on the shared tour (HearthTour.swift): Home, Assets, People, Originals and
/// Search. It shows once after onboarding and again from Profile › Take the Tour. Screens mark
/// what each step points at with `.hearthTourTarget(_:)`; a step with nothing marked shows its
/// card at the bottom.
enum TroveTour {
    static let home = "home"
    static let assets = "assets"
    static let people = "people"
    static let originals = "originals"
    static let search = "search"

    static let steps: [HearthTourStep] = [
        HearthTourStep(home, title: "Home", message: "What needs you soon: passports, registrations and policies coming up for renewal, with what renewing takes.", symbol: "archivebox", color: .blue),
        HearthTourStep(assets, title: "Assets", message: "Your home, cars and other things, each with its titles, warranties and policies.", symbol: "square.grid.2x2", color: .green),
        HearthTourStep(people, title: "People", message: "Everyone in your household and their papers: IDs, birth certificates, insurance cards.", symbol: "person.2", color: .purple),
        HearthTourStep(originals, title: "Originals", message: "Where each paper original is kept, from the fire safe to the safe deposit box.", symbol: "mappin.and.ellipse", color: .orange),
        HearthTourStep(search, title: "Search", message: "Find any document by name, person, number or what's written on it.", symbol: "magnifyingglass", color: .pink),
    ]

    static func tab(for step: HearthTourStep) -> AppTab {
        switch step.id {
        case assets: .assets
        case people: .people
        case originals: .originals
        case search: .search
        default: .home
        }
    }
}
