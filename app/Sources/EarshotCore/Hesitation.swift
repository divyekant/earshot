/// Hesitation words that speech to text writes at the start of a command: "Uh, Slack me running late".
/// The router drops them like the other lead fillers.
/// "so" counts only at the start: "so what" stays not a command, because "what" is not a command word.
public enum Hesitation {
    public static let words: Set<String> = ["uh", "uhh", "um", "umm", "uhm", "er", "erm", "ah", "hmm", "hm", "so"]
}
