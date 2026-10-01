import Foundation

enum FixtureError: Error { case missing(String) }

enum Fixture {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }
}
