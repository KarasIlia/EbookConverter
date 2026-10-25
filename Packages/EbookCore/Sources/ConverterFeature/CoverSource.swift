/// Where the current cover comes from. Precedence: custom > fromFile > generated.
public enum CoverSource: Equatable {
    case fromFile
    case generated
    case custom
}
