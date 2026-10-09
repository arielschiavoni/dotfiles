//! Profile name patterns: `*` is any run of characters (dots included, so
//! `*.agent` matches `renderer.dev.agent`), `?` one character; every other
//! character matches itself.

pub fn matches(pattern: &str, name: &str) -> bool {
    let (p, n): (Vec<char>, Vec<char>) = (pattern.chars().collect(), name.chars().collect());
    // iterative wildcard match: on a mismatch, let the last `*` eat one more
    let (mut pi, mut ni) = (0, 0);
    let mut star: Option<(usize, usize)> = None;
    while ni < n.len() {
        match p.get(pi) {
            Some('*') => {
                star = Some((pi, ni));
                pi += 1;
            }
            Some(&c) if c == '?' || c == n[ni] => {
                pi += 1;
                ni += 1;
            }
            _ => match star {
                Some((sp, sn)) => {
                    pi = sp + 1;
                    ni = sn + 1;
                    star = Some((sp, sn + 1));
                }
                None => return false,
            },
        }
    }
    p[pi..].iter().all(|&c| c == '*')
}

/// Whether any of `patterns` matches `name`.
pub fn any(patterns: &[String], name: &str) -> bool {
    patterns.iter().any(|p| matches(p, name))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn star_crosses_dots() {
        assert!(matches("*.agent", "renderer.dev.agent"));
        assert!(matches("renderer.*.agent", "renderer.dev.agent"));
        assert!(matches("*", ""));
        assert!(!matches("*.agent", "renderer.dev.admin"));
        assert!(!matches("*.agent", "renderer.dev.agent.admin"));
        assert!(!matches("*.agent", "agent"));
    }

    #[test]
    fn exact_and_question_mark() {
        assert!(matches("genius.prod.agent", "genius.prod.agent"));
        assert!(!matches("genius.prod.agent", "genius.prod.agentx"));
        assert!(matches("app.de?.agent", "app.dev.agent"));
        assert!(any(&["x".into(), "*.agent".into()], "a.agent"));
        assert!(!any(&[], "a.agent"));
    }
}
