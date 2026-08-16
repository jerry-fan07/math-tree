# Quant tree — canonical outline and spine catalog

The skeleton of `content-quant/`: 9 branches, 58 subbranches, in a **fixed
global topological order** (the `NN.` numbers). A subbranch file may reference,
besides its own nodes, ONLY the `spine` ids of subbranches with a **lower**
order number. Spine ids are a contract: if the outline assigns a spine id to
your subbranch, your file must contain a node with exactly that id and meaning.
Kinds in parentheses are the intended kind for the spine node.

Branch order on disk is by branch; authoring order is the NN numbers.

# quant-tools — Mathematical Tools
summary: The deterministic toolkit quant interviews assume in passing — series and special integrals, the linear algebra of covariance and projection, convexity and Lagrange multipliers, and recurrence methods.

## 1. quant-tools.series-calculus — Series, Sums & Special Integrals
summary: Closed forms and asymptotics that price out expectations by hand — geometric and power sums, Taylor expansions, Stirling, and the Gaussian integral.
topics:
- Geometric series and its differentiated forms (sum of n x^n)
- Arithmetic series; sums of squares and cubes
- Telescoping sums
- Harmonic numbers, H_n ≈ ln n + γ
- Taylor/Maclaurin expansions: e^x, ln(1+x), (1+x)^a, sin/cos
- The limit (1+x/n)^n → e^x
- Stirling's approximation
- Gaussian integral ∫e^{-x²/2}dx = √(2π)
- Gamma function (Γ(n)=(n-1)!, Γ(1/2)=√π) and Beta function
- AM–GM and Cauchy–Schwarz (deterministic forms)
- Exchanging order of summation (double-counting a double sum)
spine:
- `quant-tools.series-calculus.geometric-series` (theorem) — sum of ar^k, |r|<1
- `quant-tools.series-calculus.geometric-derivative` (technique) — differentiate the geometric series to get sums of k r^k
- `quant-tools.series-calculus.power-sums` (proposition) — closed forms for Σk, Σk², Σk³
- `quant-tools.series-calculus.telescoping` (technique) — collapse Σ(a_{k+1}-a_k)
- `quant-tools.series-calculus.harmonic-numbers` (proposition) — H_n ~ ln n + γ
- `quant-tools.series-calculus.taylor` (theorem) — Taylor/Maclaurin expansion with the standard examples
- `quant-tools.series-calculus.exp-limit` (proposition) — (1+x/n)^n → e^x
- `quant-tools.series-calculus.stirling` (theorem) — n! ~ √(2πn)(n/e)^n
- `quant-tools.series-calculus.gaussian-integral` (theorem) — ∫ e^{-x²/2} dx = √(2π)
- `quant-tools.series-calculus.gamma-function` (definition) — Γ and its factorial/half-integer values
- `quant-tools.series-calculus.am-gm` (theorem) — AM ≥ GM with equality iff equal
- `quant-tools.series-calculus.cauchy-schwarz` (theorem) — (Σa_ib_i)² ≤ Σa_i²Σb_i²
- `quant-tools.series-calculus.sum-exchange` (technique) — swap order of a double sum / sum–integral

## 2. quant-tools.linear-algebra — Linear Algebra for Quant
summary: Matrices as the language of portfolios and factor models — eigenstructure, positive semidefiniteness, projection and least squares, PCA.
topics:
- Matrix product, inverse, transpose; solving Ax=b
- Rank; when systems have no/one/many solutions
- Determinant as volume scaling; trace
- Eigenvalues/eigenvectors; det = product of eigenvalues, tr = sum
- Symmetric matrices: real eigenvalues, orthogonal eigenvectors (spectral theorem)
- Positive (semi)definite matrices; tests (eigenvalues, x'Ax, leading minors)
- Why covariance matrices are PSD
- Quadratic forms x'Ax
- Orthogonal projection; least squares as projection
- PCA as eigendecomposition of the covariance matrix
- Matrix powers via diagonalization (used later for Markov chains, Fibonacci)
spine:
- `quant-tools.linear-algebra.matrix-algebra` (definition) — product, inverse, transpose, and their rules
- `quant-tools.linear-algebra.rank-solvability` (proposition) — rank and the solution set of Ax=b
- `quant-tools.linear-algebra.determinant-trace` (definition) — det and tr with their meanings
- `quant-tools.linear-algebra.eigen` (definition) — eigenvalues/eigenvectors, characteristic polynomial
- `quant-tools.linear-algebra.trace-det-eigen` (proposition) — tr = Σλ, det = Πλ
- `quant-tools.linear-algebra.spectral` (theorem) — spectral theorem for symmetric matrices
- `quant-tools.linear-algebra.psd` (definition) — PSD/PD and the standard tests
- `quant-tools.linear-algebra.quadratic-form` (definition) — x'Ax and its sign behaviour
- `quant-tools.linear-algebra.projection` (theorem) — orthogonal projection minimizes distance; normal equations
- `quant-tools.linear-algebra.pca` (technique) — principal components from the covariance eigendecomposition
- `quant-tools.linear-algebra.diagonalization-powers` (technique) — computing A^n via eigendecomposition

## 3. quant-tools.optimization — Optimization & Convexity
summary: Enough optimization to derive Kelly, Markowitz and OLS — convexity, first-order conditions, and Lagrange multipliers.
topics:
- Convex sets and convex functions; second-derivative test for convexity
- Strict convexity and uniqueness of minima
- First-order condition; stationary points; local vs global under convexity
- Second-order conditions (Hessian PSD)
- Minimizing quadratics (vertex form; x'Ax with linear term)
- Lagrange multipliers for equality constraints
- KKT sketch / inequality constraints (light)
- Envelope of maxima intuition (why optima are insensitive to small parameter error)
spine:
- `quant-tools.optimization.convexity` (definition) — convex functions/sets, second-derivative characterization
- `quant-tools.optimization.foc` (proposition) — first-order condition; global minimum under convexity
- `quant-tools.optimization.quadratic-min` (proposition) — closed-form minimizer of a quadratic
- `quant-tools.optimization.lagrange` (technique) — Lagrange multipliers for equality-constrained optima
- `quant-tools.optimization.flat-optimum` (intuition) — optima are flat: first-order errors in inputs cost second-order in objective

# quant-probability — Probability
summary: The core of the quant interview — counting, conditioning, distributions, expectation technique, inequalities and limit behaviour, at solved-problem depth.

## 4. quant-probability.foundations — Probability Foundations
summary: Sample spaces, the axioms, equally likely outcomes, and independence — the ground everything else stands on.
topics:
- Sample space, events, set operations on events
- Kolmogorov axioms; finite additivity consequences
- Complement rule; P(A∪B) for two and three events (inclusion–exclusion small cases)
- Monotonicity and the union bound for two events
- Classical (equally likely) probability; relation to counting
- Independence of two events; pairwise vs mutual independence (with counterexample)
- Odds ↔ probability conversion
spine:
- `quant-probability.foundations.axioms` (axiom) — Kolmogorov axioms
- `quant-probability.foundations.complement` (corollary) — P(Aᶜ)=1−P(A) and monotonicity
- `quant-probability.foundations.union-two` (proposition) — P(A∪B)=P(A)+P(B)−P(A∩B), three-event version
- `quant-probability.foundations.classical` (definition) — equally likely outcomes: favourable/total
- `quant-probability.foundations.independence-events` (definition) — independence; pairwise vs mutual
- `quant-probability.foundations.odds` (definition) — odds and implied probability of an event

## 5. quant-probability.counting — Counting & Combinatorics
summary: Permutations, combinations and the classic identities — the counting layer under classical probability, with the interview staples worked.
topics:
- Multiplication principle
- Permutations, k-permutations, circular arrangements, arrangements with repeated letters
- Combinations; binomial coefficients; Pascal, symmetry, hockey stick, Vandermonde
- Binomial theorem
- Multinomial coefficients
- Stars and bars (both variants)
- Inclusion–exclusion (general) and derangements
- Pigeonhole principle
- Cycle decomposition of permutations; expected number of cycles (harmonic)
- Catalan numbers (balanced sequences; paths that avoid crossing)
- Birthday problem (worked, with the e^{-n²/2·365} approximation)
- Committee/bijection/double-counting proofs as a technique
spine:
- `quant-probability.counting.multiplication-principle` (proposition) — sequential choices multiply
- `quant-probability.counting.permutations` (definition) — n!, k-permutations, repeated elements
- `quant-probability.counting.combinations` (definition) — C(n,k) and its symmetry/Pascal identities
- `quant-probability.counting.binomial-theorem` (theorem) — (x+y)^n expansion
- `quant-probability.counting.multinomial` (definition) — multinomial coefficients
- `quant-probability.counting.stars-bars` (technique) — nonnegative/positive integer compositions
- `quant-probability.counting.inclusion-exclusion` (theorem) — the general alternating formula
- `quant-probability.counting.derangements` (example) — !n and the 1/e limit
- `quant-probability.counting.pigeonhole` (proposition) — n+1 pigeons, n holes
- `quant-probability.counting.permutation-cycles` (proposition) — cycle structure; expected cycles ≈ H_n
- `quant-probability.counting.catalan` (proposition) — Catalan numbers count non-crossing paths
- `quant-probability.counting.birthday-problem` (example) — collision probability, 23 people
- `quant-probability.counting.double-counting` (technique) — count one set two ways

## 6. quant-probability.conditional — Conditional Probability & Bayes
summary: Conditioning as the central move of probability interviews — chain rule, total probability, Bayes in probability and odds form, and the base-rate trap.
topics:
- Conditional probability definition; reduced sample space view
- Chain (multiplication) rule
- Law of total probability
- Bayes' theorem; prior/likelihood/posterior language
- Odds form of Bayes (posterior odds = prior odds × likelihood ratio)
- Base-rate neglect: the disease-test example fully worked
- Sampling without replacement (cards/urns) via chain rule; symmetry ("the 2nd card is an ace with prob 4/52")
- Conditional independence; independence does not survive conditioning (and vice versa)
- Simpson-style aggregation warning (pointer; full paradox lives in puzzles)
spine:
- `quant-probability.conditional.conditional-probability` (definition) — P(A|B)=P(A∩B)/P(B)
- `quant-probability.conditional.chain-rule` (proposition) — P(A₁…A_n) as a product of conditionals
- `quant-probability.conditional.total-probability` (theorem) — partition the world and average
- `quant-probability.conditional.bayes` (theorem) — Bayes' theorem
- `quant-probability.conditional.bayes-odds` (corollary) — odds form; likelihood ratio as the update
- `quant-probability.conditional.disease-test` (example) — base-rate neglect worked to the number
- `quant-probability.conditional.symmetry-exchangeability` (technique) — positions are exchangeable when drawing without replacement
- `quant-probability.conditional.conditional-independence` (definition) — A ⊥ B given C, and the traps

## 7. quant-probability.random-variables — Random Variables
summary: The machinery of distributions — CDF/PMF/PDF, quantiles, transformations, indicators, and order statistics.
topics:
- Random variable; discrete vs continuous vs mixed
- CDF and its properties; survival function
- PMF; PDF and its relation to the CDF
- Quantiles and the median
- Indicator random variables
- Functions of a random variable; monotone change of variables (density transformation)
- Probability integral transform (F(X) is uniform)
- Order statistics: distributions of min and max; density of the k-th order statistic
- Expectation deferred to its own subbranch (do not define E here)
spine:
- `quant-probability.random-variables.rv` (definition) — random variable as a numerical outcome
- `quant-probability.random-variables.cdf` (definition) — CDF properties, survival function
- `quant-probability.random-variables.pmf` (definition) — discrete law
- `quant-probability.random-variables.pdf` (definition) — density, P(a≤X≤b)=∫, relation to CDF
- `quant-probability.random-variables.quantiles` (definition) — quantile function, median
- `quant-probability.random-variables.indicator` (definition) — 1{A} as a Bernoulli variable
- `quant-probability.random-variables.transformation` (technique) — density of g(X) for monotone g
- `quant-probability.random-variables.pit` (proposition) — probability integral transform
- `quant-probability.random-variables.min-max` (proposition) — CDFs of min and max of independent variables
- `quant-probability.random-variables.order-statistics` (proposition) — density of the k-th order statistic

## 8. quant-probability.expectation — Expectation & Variance
summary: Linearity, LOTUS, tail sums and the indicator trick — the workhorse techniques that crack most interview expectations without integration.
topics:
- Expectation (discrete and continuous definitions); when it fails to exist
- LOTUS
- Linearity of expectation — no independence needed (the single most-used interview fact)
- Indicator trick: E[count] = Σ P(event); expected fixed points of a random permutation = 1
- Tail-sum formula: E[X] = Σ P(X≥k) and ∫ P(X>t) dt
- Variance; Var = E[X²] − (E X)²; Var(aX+b)
- Standard deviation; why variance is the right scale for squared error
- Median vs mean as predictors (L1 vs L2 loss)
- Symmetry arguments for expectations
spine:
- `quant-probability.expectation.expectation` (definition) — E[X] discrete/continuous, existence caveat
- `quant-probability.expectation.lotus` (theorem) — E[g(X)] without finding g(X)'s law
- `quant-probability.expectation.linearity` (theorem) — E[ΣX_i]=ΣE[X_i], always
- `quant-probability.expectation.indicator-trick` (technique) — decompose counts into indicators
- `quant-probability.expectation.fixed-points` (example) — expected fixed points of a permutation is 1
- `quant-probability.expectation.tail-sum` (proposition) — expectation as summed/integrated tails
- `quant-probability.expectation.variance` (definition) — Var, the E[X²]−(EX)² identity, scaling rules
- `quant-probability.expectation.mean-median-loss` (proposition) — mean minimizes L2, median minimizes L1
- `quant-probability.expectation.symmetry-expectation` (technique) — symmetry pins an expectation without computation

## 9. quant-probability.discrete — Discrete Distributions
summary: The named discrete laws with their means, variances and interview signatures — Bernoulli through Poisson, plus the coupon collector.
topics:
- Bernoulli; Binomial (mean/variance via indicators; mode)
- Geometric (memorylessness; mean 1/p via tail sum)
- Negative binomial
- Poisson (law, E=Var=λ, sums of independent Poissons)
- Poisson as limit of binomial (law of rare events)
- Hypergeometric (sampling without replacement; mean via indicators/symmetry)
- Discrete uniform
- Coupon collector (E = n H_n, worked)
- Expected rolls to see a six; expected tosses to first head
- Binomial vs hypergeometric: with vs without replacement
spine:
- `quant-probability.discrete.bernoulli` (definition) — the 0/1 building block
- `quant-probability.discrete.binomial` (definition) — law, mean np, variance np(1−p)
- `quant-probability.discrete.geometric` (definition) — first-success law, mean 1/p
- `quant-probability.discrete.memoryless-geometric` (proposition) — geometric memorylessness
- `quant-probability.discrete.negative-binomial` (definition) — waiting for the r-th success
- `quant-probability.discrete.poisson` (definition) — law, E=Var=λ, additivity
- `quant-probability.discrete.poisson-limit` (theorem) — binomial → Poisson as n→∞, np→λ
- `quant-probability.discrete.hypergeometric` (definition) — sampling without replacement
- `quant-probability.discrete.uniform-discrete` (definition) — equally likely values
- `quant-probability.discrete.coupon-collector` (example) — nH_n, worked for n=6 dice faces

## 10. quant-probability.continuous — Continuous Distributions
summary: Uniform, exponential, normal and friends — densities, moments, memorylessness, and the manipulations interviews expect cold.
topics:
- Continuous uniform (moments; P(U∈[a,b]) geometry)
- Exponential: density, mean/variance, memorylessness, min of exponentials, competing clocks P(X<Y)=λx/(λx+λy)
- Normal: density, standardization, 68–95–99.7, sums of independent normals
- Why the normal density integrates to 1 (Gaussian integral)
- Lognormal (multiplicative growth; E = e^{μ+σ²/2})
- Gamma (sum of exponentials), Beta (order statistics of uniforms)
- Cauchy (no mean; ratio of normals)
- Chi-square as sum of squared normals (light)
- Sum of two uniforms (triangle density; P(U₁+U₂ ≤ 1) = 1/2 style regions)
spine:
- `quant-probability.continuous.uniform` (definition) — flat density, moments
- `quant-probability.continuous.exponential` (definition) — density, mean 1/λ
- `quant-probability.continuous.memoryless-exponential` (proposition) — the continuous memoryless law
- `quant-probability.continuous.min-exponentials` (proposition) — min is exponential with summed rate; P(X<Y) race
- `quant-probability.continuous.normal` (definition) — density, standardization, empirical rule
- `quant-probability.continuous.normal-sums` (proposition) — independent normal sums stay normal
- `quant-probability.continuous.lognormal` (definition) — exp of a normal, mean e^{μ+σ²/2}
- `quant-probability.continuous.gamma` (definition) — sum of iid exponentials
- `quant-probability.continuous.beta` (definition) — Beta(a,b), uniform order statistics
- `quant-probability.continuous.cauchy` (example) — heavy tails, undefined mean
- `quant-probability.continuous.uniform-sum` (example) — triangle density and area computations

## 11. quant-probability.joint — Joint Distributions & Dependence
summary: Joint laws, covariance and correlation, convolution, and the bivariate normal — how variables move together.
topics:
- Joint PMF/PDF; marginalization
- Independence of random variables (factorization)
- Covariance: definition, bilinearity, Cov=E[XY]−E[X]E[Y]
- Correlation; bounds ±1 via Cauchy–Schwarz
- Variance of a sum (the covariance cross-terms)
- Uncorrelated ≠ independent (X and X² example)
- Convolution: distribution of a sum of independents
- Bivariate normal: marginals, conditionals are linear in the condition, ρ as full dependence descriptor
- Multivariate normal via mean vector and covariance matrix (light)
- Expected max/min of two variables via joint reasoning
spine:
- `quant-probability.joint.joint-law` (definition) — joint distributions and marginals
- `quant-probability.joint.independence-rvs` (definition) — factorizing joints
- `quant-probability.joint.covariance` (definition) — Cov and its algebra
- `quant-probability.joint.correlation` (definition) — normalized covariance in [−1,1]
- `quant-probability.joint.variance-sum` (proposition) — Var(ΣX_i) with cross-terms
- `quant-probability.joint.uncorrelated-not-independent` (example) — the standard counterexample
- `quant-probability.joint.convolution` (technique) — law of a sum of independents
- `quant-probability.joint.bivariate-normal` (proposition) — linear conditional means, ρ tells all
- `quant-probability.joint.multivariate-normal` (definition) — mean vector + covariance matrix

## 12. quant-probability.conditioning — Conditional Expectation & Tower
summary: E[X|Y] as a random variable, the tower property, total variance, and random sums — the machinery of sequential reasoning.
topics:
- Conditional distribution given an event and given a variable
- Conditional expectation E[X|Y]; as best predictor (minimizes MSE)
- Tower property (law of iterated expectations)
- Law of total variance
- Conditioning as a computational strategy (compute E by conditioning on the first thing that happens)
- Random sums: E and Var of S = X₁+…+X_N with random N
- E[X | X > t] for exponential/uniform (worked)
spine:
- `quant-probability.conditioning.conditional-expectation` (definition) — E[X|Y] as a function of Y
- `quant-probability.conditioning.tower` (theorem) — E[E[X|Y]] = E[X]
- `quant-probability.conditioning.total-variance` (theorem) — Var(X) = E[Var(X|Y)] + Var(E[X|Y])
- `quant-probability.conditioning.condition-first-step` (technique) — condition on the first event to set up equations
- `quant-probability.conditioning.random-sums` (proposition) — mean/variance of a randomly-stopped sum
- `quant-probability.conditioning.best-predictor` (proposition) — E[X|Y] minimizes mean squared error

## 13. quant-tools.recurrences — Recurrences & First-Step Analysis
summary: Turning sequential randomness into equations — first-step analysis, linear recurrences, and the pattern-waiting classics.
topics:
- Linear recurrences with constant coefficients; characteristic equation
- Fibonacci-type counting (no two consecutive heads in n tosses)
- First-step analysis for expected values and probabilities (uses conditioning)
- Boundary conditions and guessing particular solutions
- Expected tosses to see HH (=6) vs HT (=4), and why they differ
- Expected tosses to first head via first-step (recovers 1/p)
- Setting up systems of equations for multi-state problems
spine:
- `quant-tools.recurrences.linear-recurrence` (technique) — solve via characteristic roots
- `quant-tools.recurrences.first-step-analysis` (technique) — condition on step one, solve the linear system
- `quant-tools.recurrences.hh-vs-ht` (example) — 6 vs 4, with the overlap explanation
- `quant-tools.recurrences.no-consecutive-heads` (example) — Fibonacci counting of coin sequences

## 14. quant-probability.mgf — Generating Functions & Transforms
summary: PGFs and MGFs — turning convolution into multiplication and reading moments off derivatives.
topics:
- Probability generating function; extracting probabilities and factorial moments
- Moment generating function; moments from derivatives at 0
- MGF of sums of independents = product
- Standard MGFs: Bernoulli, binomial, Poisson, normal, exponential
- Uniqueness/identification (light, no proof)
- Using PGFs on dice problems (can two loaded dice give uniform sums? style)
- Characteristic function existence (one-line pointer, prominence 0)
spine:
- `quant-probability.mgf.pgf` (definition) — E[s^X] and what its derivatives encode
- `quant-probability.mgf.mgf` (definition) — E[e^{tX}], moments from derivatives
- `quant-probability.mgf.mgf-sums` (proposition) — independence turns sums into products
- `quant-probability.mgf.standard-mgfs` (proposition) — the table for the named laws
- `quant-probability.mgf.identification` (proposition) — matching transforms identifies the law

## 15. quant-probability.inequalities — Probability Inequalities
summary: Markov, Chebyshev, Jensen, Chernoff and the union bound — the standard levers for tail estimates and sanity bounds.
topics:
- Markov's inequality (and tightness)
- Chebyshev's inequality; k-sigma bounds
- Jensen's inequality (uses convexity); E[X²] ≥ (EX)², AM–GM as a special case
- Union bound (Boole), with a hashing/collision flavour example
- Chernoff bound idea: exponential Markov applied to the MGF
- Cauchy–Schwarz probabilistic form: |Cov| ≤ σ_X σ_Y
- Paley–Zygmund / second-moment method (prominence 0, light)
spine:
- `quant-probability.inequalities.markov` (theorem) — P(X≥a) ≤ E[X]/a for X≥0
- `quant-probability.inequalities.chebyshev` (theorem) — deviation bounds from variance
- `quant-probability.inequalities.jensen` (theorem) — E[φ(X)] ≥ φ(E[X]) for convex φ
- `quant-probability.inequalities.union-bound` (proposition) — P(∪A_i) ≤ ΣP(A_i)
- `quant-probability.inequalities.chernoff` (technique) — optimize e^{−ta}E[e^{tX}]
- `quant-probability.inequalities.cs-covariance` (corollary) — |Corr| ≤ 1, |Cov| ≤ σσ

## 16. quant-probability.limits — Limit Theorems
summary: LLN, CLT and the approximation toolkit — what large n buys you and how to cash it at an interview.
topics:
- Convergence in probability vs in distribution (working definitions)
- Weak law of large numbers (via Chebyshev)
- Strong law statement (no proof)
- Central limit theorem; √n scaling
- Normal approximation to binomial with continuity correction (worked: fair coin 100 tosses ≥ 60 heads)
- Poisson approximation regime vs normal regime
- Delta method (light)
- Borel–Cantelli (prominence 0)
- Monte Carlo error shrinks like n^{−1/2} (forward pointer to simulation)
spine:
- `quant-probability.limits.wlln` (theorem) — sample mean → mean, via Chebyshev
- `quant-probability.limits.slln` (theorem) — almost-sure version, statement
- `quant-probability.limits.clt` (theorem) — the CLT with its hypotheses
- `quant-probability.limits.normal-approx-binomial` (technique) — continuity-corrected normal approximation
- `quant-probability.limits.root-n` (intuition) — errors shrink like 1/√n; precision costs quadratically
- `quant-probability.limits.delta-method` (technique) — asymptotics of g(sample mean)

## 17. quant-probability.geometric — Geometric Probability
summary: Probability as area — meeting problems, stick breaking, Buffon's needle, and the Bertrand warning about "random".
topics:
- Uniform random points; probability as ratio of measures
- The meeting problem (two people, 15-minute wait) worked via area
- Breaking a stick: probability the pieces form a triangle (1/4)
- Expected lengths of broken-stick pieces
- Buffon's needle
- Bertrand's chord paradox: "uniform" needs a specified mechanism
- Random points on a circle: probability all on a semicircle
spine:
- `quant-probability.geometric.probability-as-area` (technique) — set up the square/region, take the area ratio
- `quant-probability.geometric.meeting-problem` (example) — the classic area computation
- `quant-probability.geometric.stick-triangle` (example) — 1/4 via the constraint region
- `quant-probability.geometric.buffon` (example) — needle crossings estimate π
- `quant-probability.geometric.bertrand-paradox` (example) — three answers until the mechanism is fixed
- `quant-probability.geometric.semicircle` (example) — n points on one semicircle: n/2^{n−1}

# quant-processes — Stochastic Processes
summary: Randomness with a time axis — walks, chains, martingales, stopping, Poisson arrivals, Brownian motion and the Itô calculus interviews reach for.

## 18. quant-processes.random-walks — Random Walks
summary: The simple random walk and its path-counting arsenal — reflection, ballot counting, first passages and recurrence.
topics:
- Simple symmetric random walk; increments, S_n distribution
- Path counting: paths as ±1 sequences; probability via counting
- Reflection principle
- Ballot problem
- First passage probabilities and the hitting-time distribution shape (light)
- Return to origin; P(S_{2n}=0) ~ 1/√(πn) via Stirling
- Recurrence in 1D/2D, transience in 3D (statement + intuition)
- Expected distance after n steps ~ √(2n/π)
- Maximum of a walk via reflection
- Arcsine-law intuition: leads are sticky (prominence 0)
spine:
- `quant-processes.random-walks.ssrw` (definition) — the ±1 walk and S_n's binomial law
- `quant-processes.random-walks.path-counting` (technique) — probabilities as path counts
- `quant-processes.random-walks.reflection` (theorem) — the reflection principle
- `quant-processes.random-walks.ballot` (theorem) — ballot problem (p−q)/(p+q)
- `quant-processes.random-walks.first-passage` (proposition) — hitting a level: probabilities via reflection
- `quant-processes.random-walks.return-origin` (proposition) — P(S_{2n}=0) and its Stirling asymptotics
- `quant-processes.random-walks.recurrence-dimension` (theorem) — recurrent in 1–2D, transient in 3D
- `quant-processes.random-walks.max-distribution` (proposition) — law of the running maximum

## 19. quant-processes.ruin — Gambler's Ruin
summary: The ruin family — fair and biased ruin probabilities, expected duration, and what an infinite bankroll opponent means.
topics:
- Setup: absorbing barriers at 0 and N, start at k
- Fair ruin probability k/N via first-step (or martingale later)
- Biased ruin via the (q/p)^k geometric solution
- Expected duration: k(N−k) fair case; biased formula (light)
- Ruin against an infinitely rich adversary; sure ruin for p ≤ 1/2
- Scaling intuition: doubling stakes under an edge/deficit
- Bold play vs timid play when behind (intuition)
spine:
- `quant-processes.ruin.setup` (definition) — the two-barrier absorbing walk
- `quant-processes.ruin.fair` (theorem) — ruin probability 1−k/N, fair case
- `quant-processes.ruin.biased` (theorem) — the (q/p)^k formula
- `quant-processes.ruin.duration` (proposition) — expected game length k(N−k)
- `quant-processes.ruin.infinite-opponent` (corollary) — certain ruin without an edge
- `quant-processes.ruin.bold-play` (intuition) — when behind against the house, bet big

## 20. quant-processes.markov-chains — Markov Chains
summary: Memoryless state dynamics — transition matrices, absorption equations, stationary distributions and reversibility.
topics:
- Markov property; transition matrix; n-step transitions (Chapman–Kolmogorov, matrix powers)
- State classification: communicating classes, recurrence/transience, periodicity
- Absorption probabilities via first-step linear systems
- Expected time to absorption
- Stationary distribution; existence/uniqueness conditions (irreducible + aperiodic, statement)
- Detailed balance and reversibility; random walk on a graph (π ∝ degree)
- Long-run fraction of time = stationary probability (ergodic statement)
- Classic worked chains: weather chain, mouse in a maze, drunkard on a path
- PageRank flavour (prominence 0)
spine:
- `quant-processes.markov-chains.markov-property` (definition) — the future depends only on the present
- `quant-processes.markov-chains.transition-matrix` (definition) — P, rows sum to 1, n-step = P^n
- `quant-processes.markov-chains.classification` (definition) — recurrent/transient/periodic classes
- `quant-processes.markov-chains.absorption` (technique) — absorption probabilities by first-step equations
- `quant-processes.markov-chains.absorption-time` (technique) — expected steps to absorption
- `quant-processes.markov-chains.stationary` (definition) — πP = π and when it is the limit
- `quant-processes.markov-chains.detailed-balance` (proposition) — reversibility; walk on a graph has π ∝ degree
- `quant-processes.markov-chains.ergodic-fraction` (theorem) — time averages converge to π

## 21. quant-processes.martingales — Martingales & Optional Stopping
summary: Fair games formalized — the martingale zoo, stopping times, optional stopping, and the pattern-waiting magic it enables.
topics:
- Filtration (light) and martingale definition; sub/supermartingale
- The zoo: S_n, S_n²−n, exponential/geometric martingale ((q/p)^{S_n})
- Stopping times: definition, examples and non-examples
- Optional stopping theorem with usable sufficient conditions
- Ruin probabilities via S_n and (q/p)^{S_n} martingales
- Expected hitting time via S_n²−n
- Wald's identities
- ABRACADABRA / monkey typing: expected time to a pattern via the casino-of-gamblers martingale
- Why "double after every loss" fails (unbounded stopping breaks OST)
spine:
- `quant-processes.martingales.martingale` (definition) — E[X_{n+1}|past] = X_n
- `quant-processes.martingales.examples-zoo` (proposition) — S_n, S_n²−n, (q/p)^{S_n} are martingales
- `quant-processes.martingales.stopping-time` (definition) — decisions using only the past
- `quant-processes.martingales.ost` (theorem) — optional stopping with its conditions
- `quant-processes.martingales.ruin-via-ost` (example) — both ruin formulas in three lines
- `quant-processes.martingales.wald` (theorem) — Wald's identity for random sums
- `quant-processes.martingales.abracadabra` (example) — pattern waiting times via betting teams
- `quant-processes.martingales.martingale-betting-fallacy` (example) — doubling down and why OST forbids the free lunch

## 22. quant-processes.stopping — Optimal Stopping
summary: When to stop — backward induction, the dice re-roll games, and the secretary problem's 1/e rule.
topics:
- Finite-horizon backward induction; value of continuation vs stopping
- The dice game: one roll, value 3.5; up to two rolls, 4.25; up to three, 14/3 — fully worked
- Re-roll games with fees; when to pay to continue
- One-step lookahead rule and when it is optimal (monotone problems, light)
- Secretary problem: the 37% rule, sketch of why
- House-selling / search with recall vs without (light)
- American-option flavour of early exercise (pointer forward)
spine:
- `quant-processes.stopping.backward-induction` (technique) — solve the last stage first
- `quant-processes.stopping.dice-game` (example) — the 3.5 / 4.25 / 14/3 ladder
- `quant-processes.stopping.one-step-lookahead` (technique) — stop when stopping beats one more step
- `quant-processes.stopping.secretary` (example) — skip n/e then take the best so far

## 23. quant-processes.poisson — Poisson Processes
summary: Memoryless arrivals — exponential gaps, superposition and thinning, conditional uniformity, and the inspection paradox.
topics:
- Counting-process definition; independent stationary increments
- Interarrival times are iid exponential
- Superposition of independent Poisson processes
- Thinning/splitting by coin flips
- Which process fires first (rate races)
- Conditional uniformity: given N(t)=n, arrivals look like n uniforms
- Inspection paradox: the interval you land in is longer
- Compound Poisson (mean/variance via random sums)
spine:
- `quant-processes.poisson.pp` (definition) — the counting process axioms
- `quant-processes.poisson.interarrival` (theorem) — iid Exp(λ) gaps
- `quant-processes.poisson.superposition` (proposition) — rates add
- `quant-processes.poisson.thinning` (proposition) — independent thinned processes
- `quant-processes.poisson.conditional-uniformity` (theorem) — arrivals given the count are uniform
- `quant-processes.poisson.inspection-paradox` (example) — waiting for a bus takes longer than it should

## 24. quant-processes.brownian — Brownian Motion
summary: The continuum limit of the walk — Gaussian increments, scaling, reflection, hitting times and the running maximum.
topics:
- Definition: independent Gaussian increments, continuity; BM as CLT limit of walks
- Scaling and symmetry properties; √t magnitude
- Non-differentiability intuition
- Reflection principle for BM; law of the running maximum M_t
- Hitting time of a level: distribution and infinite expectation
- BM with drift: hitting probabilities via the exponential martingale
- Quadratic variation ⟨B⟩_t = t (the heart of Itô)
- Zero-crossing / arcsine flavour (prominence 0)
spine:
- `quant-processes.brownian.bm` (definition) — standard Brownian motion
- `quant-processes.brownian.scaling` (proposition) — self-similarity, √t scale
- `quant-processes.brownian.reflection-bm` (theorem) — P(M_t ≥ a) = 2P(B_t ≥ a)
- `quant-processes.brownian.hitting-time` (proposition) — hitting a level: sure but with infinite mean
- `quant-processes.brownian.drift-hitting` (proposition) — hitting probabilities under drift
- `quant-processes.brownian.quadratic-variation` (theorem) — (dB)² accumulates as dt

## 25. quant-processes.ito — Stochastic Calculus
summary: Itô's lemma and the SDEs quants actually use — GBM solved, OU as mean reversion, and why (dB)²=dt changes the chain rule.
topics:
- The Itô integral idea; why ordinary calculus fails for BM
- (dB)² = dt heuristic from quadratic variation
- Itô's lemma (one-dimensional, with the second-order term)
- GBM: dS = μS dt + σS dB solved to S_t = S₀e^{(μ−σ²/2)t + σB_t}
- Why the −σ²/2: volatility drag / geometric vs arithmetic mean
- Ornstein–Uhlenbeck: mean reversion, stationary variance σ²/2θ
- Itô isometry (light)
- Martingale condition: driftless ⇒ martingale (light)
spine:
- `quant-processes.ito.ito-lemma` (theorem) — the stochastic chain rule
- `quant-processes.ito.gbm` (proposition) — geometric Brownian motion solved
- `quant-processes.ito.vol-drag` (intuition) — the −σ²/2 as compounding drag
- `quant-processes.ito.ou` (definition) — the OU process and its mean-reverting behaviour
- `quant-processes.ito.driftless-martingale` (proposition) — no dt term ⇒ martingale

# quant-statistics — Statistics & Data
summary: Inference for people who bet on it — estimation, testing, regression, Bayesian updating, time-series behaviour of markets, simulation, and the overfitting discipline of ML.

## 26. quant-statistics.descriptive — Descriptive Statistics
summary: Sample summaries and their failure modes — means vs medians, variance estimates, and correlation read off data.
topics:
- Sample mean, sample variance (why n−1 — pointer to estimation), standard error
- Median, quantiles, IQR; robustness to outliers
- Skewness and what mean>median signals; kurtosis as tail weight
- Sample correlation; sensitivity to outliers and to nonlinearity
- Winsorizing/trimming (light)
- Aggregation warning: averages of averages
spine:
- `quant-statistics.descriptive.sample-mean` (definition) — x̄ and its standard error
- `quant-statistics.descriptive.sample-variance` (definition) — s² with the n−1 convention
- `quant-statistics.descriptive.robustness` (proposition) — median/IQR survive outliers; mean/variance do not
- `quant-statistics.descriptive.sample-correlation` (definition) — r and its pitfalls
- `quant-statistics.descriptive.skew-kurtosis` (definition) — shape beyond mean and variance

## 27. quant-statistics.estimation — Estimation
summary: Estimators judged by bias, variance and MSE — MLE and method of moments, the Cramér–Rao floor, and the German tank problem.
topics:
- Estimator, bias, variance, MSE; bias–variance decomposition
- Unbiasedness of s² (why n−1)
- Maximum likelihood: recipe and worked examples (Bernoulli p, normal μ,σ², uniform θ)
- Method of moments
- Consistency (light); MLE asymptotics (statement)
- Fisher information and Cramér–Rao lower bound (statement + one use)
- Sufficiency (light)
- German tank problem (max-based estimator, worked)
spine:
- `quant-statistics.estimation.bias-mse` (definition) — bias, variance, MSE = bias² + var
- `quant-statistics.estimation.nminus1` (proposition) — E[s²]=σ² with the n−1 divisor
- `quant-statistics.estimation.mle` (technique) — maximize the likelihood; the standard worked cases
- `quant-statistics.estimation.mom` (technique) — match sample to population moments
- `quant-statistics.estimation.cramer-rao` (theorem) — the variance floor from Fisher information
- `quant-statistics.estimation.german-tank` (example) — estimating N from the sample max

## 28. quant-statistics.testing — Hypothesis Testing & Confidence
summary: Errors, power and p-values without folklore — z and t tests, confidence intervals, and the multiple-testing trap quant research lives in.
topics:
- Null/alternative; test statistic; rejection region
- Type I/II errors, significance level, power; the tradeoff
- p-value: precise definition and the standard misreadings
- z-test; t-test and the t-distribution (heavier tails, df)
- Confidence intervals; duality with tests; the √n width shrink
- Sample-size reasoning (how many samples to detect an edge of given size)
- Multiple testing: family-wise error, Bonferroni; data snooping in strategy research
- Practical vs statistical significance
spine:
- `quant-statistics.testing.type-errors` (definition) — Type I/II, α, power
- `quant-statistics.testing.pvalue` (definition) — what a p-value is and is not
- `quant-statistics.testing.ztest` (technique) — the z-test recipe
- `quant-statistics.testing.ttest` (technique) — t-test and when the t-distribution matters
- `quant-statistics.testing.ci` (definition) — confidence intervals and test duality
- `quant-statistics.testing.sample-size` (technique) — n to resolve an effect: the (σ/effect)² law
- `quant-statistics.testing.multiple-testing` (proposition) — Bonferroni and the data-snooping hazard

## 29. quant-statistics.regression — Regression
summary: OLS from three angles — calculus, projection and covariance — plus Gauss–Markov, R², regression to the mean, and regularization.
topics:
- The linear model; least squares objective
- OLS via calculus (normal equations); via projection (geometry)
- Simple-regression slope β = Cov(x,y)/Var(x); intercept
- Gauss–Markov (statement, assumptions)
- R² and what it does/doesn't mean
- Regression to the mean (and the fallacy)
- Residual diagnostics; heteroskedasticity (light); multicollinearity
- Omitted-variable bias (direction heuristic)
- Ridge and lasso; shrinkage as bias for variance
spine:
- `quant-statistics.regression.ols` (technique) — least squares and the normal equations
- `quant-statistics.regression.beta-cov-var` (proposition) — slope as Cov/Var
- `quant-statistics.regression.projection-view` (intuition) — fitted values are a projection
- `quant-statistics.regression.gauss-markov` (theorem) — BLUE under the classical assumptions
- `quant-statistics.regression.r-squared` (definition) — variance explained, with caveats
- `quant-statistics.regression.regression-to-mean` (proposition) — extreme observations revert
- `quant-statistics.regression.omitted-variable` (proposition) — bias from a missing regressor
- `quant-statistics.regression.ridge-lasso` (technique) — penalized regression, bias–variance trade

## 30. quant-statistics.bayesian — Bayesian Inference
summary: Priors updated by likelihoods — beta–binomial coin flipping, normal–normal shrinkage, and betting on posteriors.
topics:
- The Bayesian recipe: prior × likelihood ∝ posterior
- Conjugacy; beta–binomial fully worked (posterior mean interpolates prior and data)
- Normal–normal updating; precision-weighted averaging
- Posterior predictive (light)
- Laplace's rule of succession
- Choosing priors; uniform ≠ uninformative (light)
- Bayesian vs frequentist reading of an interval
- Shrinkage intuition: small samples borrow strength from the prior
spine:
- `quant-statistics.bayesian.posterior` (technique) — the update recipe
- `quant-statistics.bayesian.conjugate` (definition) — conjugate families and why they matter
- `quant-statistics.bayesian.beta-binomial` (example) — coin-bias updating worked end to end
- `quant-statistics.bayesian.normal-normal` (example) — precision-weighted posterior mean
- `quant-statistics.bayesian.succession` (proposition) — Laplace's (k+1)/(n+2)
- `quant-statistics.bayesian.shrinkage` (intuition) — pull estimates toward the prior when data is thin

## 31. quant-statistics.time-series — Time Series
summary: Serial dependence and mean reversion — AR(1), autocorrelation, unit roots, and the stylized facts of returns.
topics:
- Weak stationarity; white noise
- Autocorrelation function; sample ACF and its ±2/√n bands (light)
- AR(1): stationarity |φ|<1, mean reversion speed, variance σ²/(1−φ²)
- MA(1); AR vs MA signatures
- Random walk as φ=1; unit roots and spurious regression warning
- Half-life of mean reversion from φ
- OU as continuous-time AR(1) (relates)
- Stylized facts: returns nearly uncorrelated, squared returns autocorrelated (volatility clustering)
spine:
- `quant-statistics.time-series.stationarity` (definition) — weak stationarity, white noise
- `quant-statistics.time-series.acf` (definition) — autocorrelation function and its reading
- `quant-statistics.time-series.ar1` (definition) — the AR(1) law, variance and reversion
- `quant-statistics.time-series.unit-root` (proposition) — φ=1 changes everything; spurious regression
- `quant-statistics.time-series.half-life` (technique) — half-life = ln 2 / ln(1/φ)
- `quant-statistics.time-series.vol-clustering` (proposition) — the stylized facts of return series

## 32. quant-statistics.simulation — Monte Carlo & Simulation
summary: Estimating by sampling — inverse transform, rejection, Box–Muller, bootstrap, and squeezing variance out of an estimator.
topics:
- Monte Carlo estimation; error ~ σ/√n (uses CLT); estimating π
- Inverse transform sampling (uses PIT)
- Rejection sampling
- Box–Muller for normals
- Simulating discrete laws; alias method (prominence 0)
- Bootstrap: resampling for standard errors
- Variance reduction: antithetic variates, control variates, importance sampling (light)
- Seeding/reproducibility hygiene (intuition)
spine:
- `quant-statistics.simulation.monte-carlo` (technique) — estimate expectations by sampling
- `quant-statistics.simulation.estimate-pi` (example) — the quarter-circle dartboard
- `quant-statistics.simulation.inverse-transform` (technique) — F^{-1}(U) has law F
- `quant-statistics.simulation.rejection` (technique) — accept/reject under an envelope
- `quant-statistics.simulation.box-muller` (technique) — two uniforms to two normals
- `quant-statistics.simulation.bootstrap` (technique) — resample to estimate sampling error
- `quant-statistics.simulation.control-variates` (technique) — subtract a correlated known-mean quantity

## 33. quant-statistics.learning — Statistical Learning
summary: The overfitting discipline — bias–variance, validation, regularization, gradient descent, and leakage, the sin quant research is built to avoid.
topics:
- Supervised learning setup; in-sample vs out-of-sample error
- Overfitting; bias–variance tradeoff (uses MSE decomposition)
- Train/validation/test; cross-validation
- Regularization as complexity control (ties to ridge/lasso)
- Gradient descent; learning rate intuition; stochastic variant (light)
- Logistic regression (light); classification metrics: precision/recall, ROC-AUC (light)
- Trees and ensembles in one node (light)
- Feature leakage and look-ahead bias — the cardinal sin in trading research
spine:
- `quant-statistics.learning.overfitting` (definition) — fitting noise; in/out-of-sample gap
- `quant-statistics.learning.bias-variance` (theorem) — the tradeoff, from the MSE decomposition
- `quant-statistics.learning.cross-validation` (technique) — honest error estimates by splitting
- `quant-statistics.learning.gradient-descent` (technique) — follow the negative gradient
- `quant-statistics.learning.leakage` (proposition) — look-ahead/leakage invalidates a backtest

# quant-mental — Mental Math & Estimation
summary: The arithmetic and estimation layer of trading interviews — exact tricks, controlled approximations, Fermi decomposition, and playing timed games well.

## 34. quant-mental.arithmetic — Mental Arithmetic
summary: Exact mental computation under time pressure — complements, anchored squares, fraction–decimal fluency, and fast checks.
topics:
- Complements to 10/100/1000 for addition/subtraction
- Multiplying near a base: (a+b)(a−b), squaring near 50/100, (x±h)² expansion
- 11s, 5s, 25s shortcuts; halving–doubling
- Fraction ↔ decimal table: 1/6, 1/7 (0.142857 cycle), 1/8, 1/9, 1/11, 1/12, 1/16
- Percentage composition: +20% then −20% ≠ 0; sequential percent changes multiply
- Weighted averages (mixing) done mentally
- Digit-sum (mod 9) and last-digit checks
- Divisibility rules (3, 4, 7, 8, 9, 11)
spine:
- `quant-mental.arithmetic.base-tricks` (technique) — complements and near-base multiplication
- `quant-mental.arithmetic.squares` (technique) — squaring via (x±h)² and difference of squares
- `quant-mental.arithmetic.fraction-decimal` (technique) — the fluency table with the 1/7 cycle
- `quant-mental.arithmetic.percent-composition` (technique) — percent changes compose multiplicatively
- `quant-mental.arithmetic.digit-checks` (technique) — mod-9 and last-digit verification
- `quant-mental.arithmetic.weighted-average` (technique) — mixing quantities by weights

## 35. quant-mental.approximation — Approximation Toolkit
summary: Controlled error at speed — rule of 72, small-x expansions, root and log estimates, and powers of two.
topics:
- Rule of 72 (and 69.3); doubling times
- ln(1+x) ≈ x − x²/2; e^x ≈ 1+x+x²/2; when the error matters
- (1+x)^n ≈ 1+nx and compounding corrections
- Square-root estimation: linearization √(a²+b) ≈ a + b/2a; one Newton step
- Anchors: ln 2 ≈ 0.693, ln 10 ≈ 2.303, log₁₀2 ≈ 0.301, e ≈ 2.718, √2, √3, √5, π²≈9.87
- 2^10 ≈ 10³ and quick order-of-magnitude via bits
- Interest/growth: annualizing, converting between horizons (√t vol scaling pointer)
- Quick normal quantiles: ±1σ 68%, ±1.645σ 90%, ±1.96σ 95%
spine:
- `quant-mental.approximation.rule-72` (technique) — doubling time ≈ 72/rate
- `quant-mental.approximation.log-linearization` (technique) — ln(1+x)≈x and friends, with error size
- `quant-mental.approximation.sqrt-estimate` (technique) — roots by linearization/Newton
- `quant-mental.approximation.anchors` (technique) — the constants worth memorizing
- `quant-mental.approximation.powers-of-two` (technique) — 2^10≈10³ scaling
- `quant-mental.approximation.normal-quantiles` (technique) — the σ→probability table

## 36. quant-mental.fermi — Fermi Estimation
summary: Decompose, bound, and multiply — order-of-magnitude estimation with error you can account for.
topics:
- Decomposition into estimable factors
- Geometric mean of bounds (if between 10k and 1M, guess 100k)
- Log-scale thinking: errors multiply, so log-errors add
- Anchor inventory: populations, areas, rates, sizes
- Dimensional/unit consistency as a check
- Worked classics: piano tuners, windows in a city, weight of a 747
- Stating assumptions out loud (interview craft)
spine:
- `quant-mental.fermi.decomposition` (technique) — factor the unknown into knowns
- `quant-mental.fermi.geometric-mean-bounds` (technique) — average bounds in log space
- `quant-mental.fermi.log-error` (intuition) — multiplicative errors add on the log scale
- `quant-mental.fermi.dimensional-check` (technique) — units must balance

## 37. quant-mental.game-tactics — Playing Timed Games
summary: Meta-skill for arithmetic and estimation games — speed–accuracy tradeoffs, when to guess, and error control under a clock.
topics:
- Scoring-aware play: expected points of attempt vs skip under penalties (uses expectation)
- When to guess: indifference thresholds from the scoring rule
- Speed–accuracy: error rate rises nonlinearly near your speed limit
- Checking cheaply: parity, last digit, magnitude before submitting
- Sequencing: bank easy points first
- Composure: fixed routines reduce variance (intuition)
spine:
- `quant-mental.game-tactics.guessing-ev` (technique) — compute the EV of a guess from the scoring rule
- `quant-mental.game-tactics.speed-accuracy` (intuition) — the error curve bends up near max speed
- `quant-mental.game-tactics.cheap-checks` (technique) — one-second verifications before answering

# quant-games — Betting, Games & Market Making
summary: Money on the line — expected-value games, Kelly sizing, game theory, auctions, betting markets, and the market-making game the trading interview is famous for.

## 38. quant-games.ev-games — Expected-Value Games
summary: Pricing simple games — fair value, symmetry, options to re-roll, and when variance should change your answer.
topics:
- Fair value of a game = expected payoff; willingness to pay
- Dice games: single roll, pay-per-point; re-roll options (uses optimal stopping)
- Card games: drawing for value, expected position of aces, stopping on colors
- Symmetry pricing (expected value pinned by symmetry before any computation)
- Conditioning on the first draw/roll
- Utility caveat: EV maximization vs risk aversion; when to refuse a positive-EV bet
- Sizing preview: repeated favorable games (pointer to Kelly)
spine:
- `quant-games.ev-games.fair-value` (definition) — price a game at its expected payoff
- `quant-games.ev-games.dice-reroll` (example) — re-roll games priced by backward induction
- `quant-games.ev-games.symmetry-pricing` (technique) — symmetry answers before algebra
- `quant-games.ev-games.risk-aversion` (intuition) — EV is not the whole answer at size

## 39. quant-games.kelly — Kelly & Bankroll
summary: Bet sizing as log-wealth optimization — the Kelly fraction, what over-betting destroys, and fractional Kelly in practice.
topics:
- Repeated bets compound: growth rate = E[ln(wealth ratio)]
- Kelly for even-money bets: f* = 2p − 1
- General odds: f* = (bp − q)/b, derived via calculus
- Growth rate curve: zero at 0 and 2f*, max at f*; over-betting twice Kelly kills growth
- Volatility drag connection (ties to −σ²/2)
- Fractional Kelly: estimation error and variance reasons
- Kelly with simultaneous/correlated bets (light)
- Bankroll ruin: fixed-fraction betting never ruins but drawdowns are brutal
spine:
- `quant-games.kelly.log-growth` (proposition) — maximize expected log wealth for long-run growth
- `quant-games.kelly.kelly-fraction` (theorem) — f* = (bp−q)/b, with the even-money special case
- `quant-games.kelly.overbetting` (proposition) — the growth curve and the 2× Kelly cliff
- `quant-games.kelly.fractional` (technique) — half-Kelly as insurance against edge misestimation

## 40. quant-games.game-theory — Game Theory
summary: Strategic play — dominance, Nash, mixed strategies via indifference, minimax in zero-sum games, and backward induction.
topics:
- Normal-form games; dominant/dominated strategies; iterated elimination
- Nash equilibrium; existence statement
- Mixed strategies; the indifference principle for computing them
- Matching pennies and RPS worked
- Zero-sum games and minimax; value of a game
- Sequential games; backward induction; credible threats
- Guess-2/3-of-average; levels of reasoning
- Prisoner's dilemma; repeated-game cooperation (light)
- First-mover vs second-mover advantage examples
spine:
- `quant-games.game-theory.dominance` (definition) — dominant strategies and elimination
- `quant-games.game-theory.nash` (definition) — mutual best response
- `quant-games.game-theory.mixed-indifference` (technique) — make the opponent indifferent
- `quant-games.game-theory.minimax` (theorem) — zero-sum value and minimax
- `quant-games.game-theory.backward-induction-games` (technique) — solve sequential games from the end
- `quant-games.game-theory.two-thirds` (example) — iterated reasoning to zero (and where humans stop)

## 41. quant-games.auctions — Auctions & Winner's Curse
summary: Bidding under uncertainty — Vickrey truthfulness, first-price shading, and the winner's curse that haunts common-value auctions.
topics:
- Auction formats: English, Dutch, first-price sealed, second-price sealed
- Second-price: truthful bidding is dominant (the proof)
- First-price: shade below value; equilibrium shading n−1/n under uniform values (light)
- Private vs common values
- Winner's curse: winning is bad news about your estimate; adjust bids down
- Jar-of-coins auction as the interview classic
- Revenue equivalence (statement, prominence 0)
spine:
- `quant-games.auctions.formats` (definition) — the four standard formats
- `quant-games.auctions.vickrey` (theorem) — second-price truthfulness
- `quant-games.auctions.shading` (proposition) — first-price equilibrium shading
- `quant-games.auctions.winners-curse` (proposition) — conditioning on winning lowers value
- `quant-games.auctions.jar-of-coins` (example) — the curse played live

## 42. quant-games.betting-markets — Odds & Betting Markets
summary: Odds as prices — implied probability, the bookmaker's overround, Dutch books, and hedging bets.
topics:
- Odds formats (decimal, fractional, American) and conversion
- Implied probability; vig/overround: implied probs sum > 1
- De-vigging: normalizing to fair probabilities
- Dutch book / arbitrage across bookmakers; stake allocation for equal profit
- EV of a bet from your probability vs implied
- Hedging an existing bet; locking in profit
- Line movement as information; sharp vs square money (intuition)
spine:
- `quant-games.betting-markets.implied-probability` (definition) — odds to probability in all formats
- `quant-games.betting-markets.overround` (definition) — the bookmaker margin
- `quant-games.betting-markets.dutch-book` (technique) — arbitrage stakes across books
- `quant-games.betting-markets.bet-ev` (technique) — edge = your p × payout − 1
- `quant-games.betting-markets.hedging-bets` (technique) — offsetting stakes to lock outcomes

## 43. quant-games.market-making-game — The Market-Making Game
summary: "Make me a market on X" — fair value first, width from uncertainty, updating on trades, adverse selection, and calibrated confidence.
topics:
- The game protocol: quote a bid and ask; interviewer trades against you; mark to truth
- Fair value first: Fermi-estimate the quantity before quoting
- Width from uncertainty: quote wide when your CI is wide; tighten as you learn
- Never cross yourself; keep bid < ask; sizing consistent with bankroll (Kelly pointer)
- Updating: a lift is evidence the truth is above your ask (Bayesian update on flow)
- Adverse selection: informed counterparties pick you off; the quote is an option you sold
- Inventory management: skew quotes to reduce accumulated risk
- Calibration: 90% intervals should contain truth 90% of the time; most people are overconfident
- Worked example: making a market on a trivia quantity, three rounds of updates
spine:
- `quant-games.market-making-game.protocol` (definition) — the rules of the interview game
- `quant-games.market-making-game.width-uncertainty` (technique) — spread ↔ confidence interval
- `quant-games.market-making-game.update-on-flow` (technique) — trades are information; move the market
- `quant-games.market-making-game.adverse-selection` (definition) — informed flow makes your quotes losses
- `quant-games.market-making-game.quote-skewing` (technique) — lean quotes against inventory
- `quant-games.market-making-game.calibration` (technique) — honest intervals, measured by hit rate

# quant-finance — Finance & Markets
summary: Instruments, no-arbitrage pricing, options and their Greeks, portfolio mathematics, risk measures, and how markets actually execute trades.

## 44. quant-finance.instruments — Instruments & Market Basics
summary: The vocabulary layer — stocks, bonds, forwards, futures and options as contracts, plus short selling and leverage.
topics:
- Equity: shares, dividends, total return
- Bonds: coupons, YTM, price–yield inverse relation; duration (light)
- Indices and ETFs
- Forwards vs futures: OTC vs exchange, margin and marking to market
- Options vocabulary: call/put, strike, expiry, European/American, long/short
- Short selling mechanics; borrow costs
- Leverage and margin; the double-edge
- Interest and discounting: PV/FV, continuous compounding
spine:
- `quant-finance.instruments.discounting` (definition) — PV/FV, continuous compounding e^{rT}
- `quant-finance.instruments.equity` (definition) — shares and dividends
- `quant-finance.instruments.bond-ytm` (definition) — price–yield relation
- `quant-finance.instruments.forward-future` (definition) — the two delivery contracts
- `quant-finance.instruments.option-vocab` (definition) — the option contract terms
- `quant-finance.instruments.short-selling` (definition) — profiting from declines, with the risks
- `quant-finance.instruments.leverage` (definition) — margin amplifies both directions

## 45. quant-finance.arbitrage — No-Arbitrage & Parity
summary: Pricing by replication — law of one price, cost of carry, put–call parity, and the option bounds every interview checks.
topics:
- Arbitrage definition; law of one price
- Replication: two portfolios with identical payoffs have identical prices
- Forward pricing F = S e^{rT}; with dividends/carry
- Cash-and-carry arbitrage when violated
- Put–call parity C − P = S − Ke^{−rT}; dividend adjustment; the conversion trade
- Option price bounds: C ≤ S, C ≥ (S − Ke^{−rT})⁺, P ≤ Ke^{−rT}
- American call on non-dividend stock: never exercise early (via bounds)
- Triangular FX arbitrage example
spine:
- `quant-finance.arbitrage.no-arbitrage` (axiom) — no free lunch; law of one price
- `quant-finance.arbitrage.replication` (technique) — price by building the same payoff
- `quant-finance.arbitrage.forward-pricing` (theorem) — F = Se^{rT} by cash-and-carry
- `quant-finance.arbitrage.put-call-parity` (theorem) — C − P = S − Ke^{−rT}
- `quant-finance.arbitrage.option-bounds` (proposition) — the model-free bounds
- `quant-finance.arbitrage.no-early-exercise` (corollary) — American calls without dividends wait

## 46. quant-finance.options — Option Pricing
summary: From payoff diagrams to Black–Scholes — binomial replication, risk-neutral probability, implied volatility, and the strategy payoffs.
topics:
- Payoff and P&L diagrams; intrinsic vs time value; moneyness
- One-step binomial pricing by replication (Δ shares + bond)
- Risk-neutral probability q = (e^{rΔt}−d)/(u−d); pricing as discounted expectation
- Multi-step binomial; dynamic replication idea
- Black–Scholes formula (statement, assumptions, uses GBM)
- Reading BS: N(d₂) as risk-neutral exercise probability (light)
- Implied volatility; smile/skew (light)
- Strategies: straddle, strangle, spreads, butterfly — payoffs and when to hold them
- Volatility bet: options as vega instruments (intuition)
spine:
- `quant-finance.options.payoff-diagrams` (technique) — draw payoff and P&L at expiry
- `quant-finance.options.binomial-pricing` (technique) — one-step replication pricing
- `quant-finance.options.risk-neutral` (theorem) — the q-measure and pricing as expectation
- `quant-finance.options.black-scholes` (theorem) — the formula and its assumptions
- `quant-finance.options.implied-vol` (definition) — the vol that matches the market price
- `quant-finance.options.straddle` (definition) — straddles/strangles as volatility positions

## 47. quant-finance.greeks — Greeks & Hedging
summary: Sensitivities as risk language — delta through vega, hedging mechanics, the gamma–theta bargain, and the ATM approximations traders quote.
topics:
- Delta: sensitivity, hedge ratio, ~N(d₁); call+put deltas
- Gamma: convexity; largest ATM near expiry
- Theta: time decay; who earns it and why
- Vega: vol sensitivity; largest ATM, grows with √T
- Rho (light)
- Delta hedging mechanics: rebalance to flat; hedging P&L = realized-vs-implied vol
- Gamma–theta tradeoff: Θ ≈ −½σ²S²Γ (relates Itô)
- Gamma scalping intuition
- ATM approximations: ATM call ≈ 0.4σS√T; straddle ≈ 0.8σS√T
- Put–call delta and parity Greeks consistency
spine:
- `quant-finance.greeks.delta` (definition) — slope, hedge ratio, N(d₁)
- `quant-finance.greeks.gamma` (definition) — curvature of value in spot
- `quant-finance.greeks.theta` (definition) — time decay
- `quant-finance.greeks.vega` (definition) — sensitivity to volatility
- `quant-finance.greeks.delta-hedging` (technique) — flatten delta, earn/pay the vol difference
- `quant-finance.greeks.gamma-theta` (proposition) — the Θ ≈ −½σ²S²Γ balance
- `quant-finance.greeks.atm-approx` (technique) — 0.4σS√T and the straddle rule of thumb

## 48. quant-finance.portfolio — Portfolio Theory
summary: Diversification quantified — portfolio variance, the frontier, Sharpe, beta, and why breadth of independent bets is the whole business.
topics:
- Portfolio return and variance (two-asset; matrix form)
- Diversification: variance of equal-weight portfolio → average covariance
- Correlation drives the benefit; the ρ=1 and ρ=−1 extremes
- Minimum-variance portfolio (two-asset closed form)
- Efficient frontier (concept); tangency portfolio (light)
- Sharpe ratio; annualization √252
- CAPM and beta; alpha as residual
- Fundamental law flavour: IR ≈ IC·√breadth — uncorrelated bets compound skill
spine:
- `quant-finance.portfolio.portfolio-variance` (proposition) — w'Σw and the two-asset case
- `quant-finance.portfolio.diversification` (theorem) — average covariance is the floor
- `quant-finance.portfolio.min-variance` (proposition) — the two-asset minimum-variance weights
- `quant-finance.portfolio.sharpe` (definition) — excess return per unit risk, annualized
- `quant-finance.portfolio.beta-capm` (definition) — beta as regression slope; CAPM line
- `quant-finance.portfolio.breadth` (proposition) — IR grows like √(independent bets)

## 49. quant-finance.risk — Risk Management
summary: Losing gracefully — VaR and expected shortfall, fat tails, drawdowns, vol scaling and the ways leverage meets ruin.
topics:
- VaR: definition, normal-VaR computation, limitations (not subadditive, silent on tail)
- Expected shortfall
- Fat tails: kurtosis in returns, normal underestimates extremes
- Vol scaling: σ√t rule and when it fails (autocorrelation)
- Drawdown; time to recover; drawdown vs volatility
- Leverage and ruin: connection to gambler's ruin and Kelly
- Correlation breakdown in stress; diversification failing when needed
- Position limits and stop rules (light)
spine:
- `quant-finance.risk.var` (definition) — the α-quantile loss, normal-case formula
- `quant-finance.risk.expected-shortfall` (definition) — mean loss beyond VaR
- `quant-finance.risk.fat-tails` (proposition) — excess kurtosis and its consequences
- `quant-finance.risk.vol-scaling` (technique) — σ√t and its assumptions
- `quant-finance.risk.drawdown` (definition) — peak-to-trough and recovery arithmetic
- `quant-finance.risk.leverage-ruin` (proposition) — leverage turns volatility into ruin probability

## 50. quant-finance.microstructure — Market Microstructure
summary: How prices actually form — the limit order book, spread economics, adverse selection at the quote, and market impact.
topics:
- Limit order book: bids, asks, depth, price–time priority
- Market vs limit orders; the taker/maker tradeoff
- Mid price; weighted mid/microprice
- Bid–ask spread components: adverse selection, inventory, processing costs
- Glosten–Milgrom intuition: spreads exist because some traders know more
- Inventory risk and quote skewing (ties to the game)
- Market impact: trading moves price; square-root law (statement)
- Execution: VWAP/TWAP, slicing (light)
- Tick size, queue position value (light)
- Latency arms race (intuition, prominence 0)
spine:
- `quant-finance.microstructure.lob` (definition) — the order book and priority rules
- `quant-finance.microstructure.order-types` (definition) — market vs limit and their tradeoff
- `quant-finance.microstructure.microprice` (definition) — size-weighted mid as fair value
- `quant-finance.microstructure.spread-components` (proposition) — why the spread is nonzero
- `quant-finance.microstructure.glosten-milgrom` (theorem) — spreads from asymmetric information
- `quant-finance.microstructure.market-impact` (proposition) — impact grows like √size

# quant-puzzles — Brainteasers & Logic
summary: The puzzle round — reusable strategies first, then the classics, the probability paradoxes, and take-away games, each worked to its answer.

## 51. quant-puzzles.strategies — Puzzle Strategies
summary: The moves that crack puzzles — invariants, parity, symmetry, extremal arguments, coloring, and working backwards.
topics:
- Invariants and monovariants; conserved quantities decide reachability
- Parity arguments
- Symmetry and pairing strategies (mirroring an opponent)
- Extremal principle (consider the largest/smallest/first)
- Coloring arguments (domino tiling of mutilated chessboard)
- Working backwards from the goal
- Adversary/worst-case thinking; guarantees vs expectations
- State-space search framing (relates programming BFS)
- Information-theoretic lower bounds (you need log₂ answers' worth of questions)
spine:
- `quant-puzzles.strategies.invariant` (technique) — find what never changes
- `quant-puzzles.strategies.parity` (technique) — mod-2 obstructions
- `quant-puzzles.strategies.symmetry-strategy` (technique) — mirror to force a draw or win
- `quant-puzzles.strategies.extremal` (technique) — look at the extreme element
- `quant-puzzles.strategies.coloring` (technique) — color to expose an imbalance
- `quant-puzzles.strategies.working-backwards` (technique) — invert the problem
- `quant-puzzles.strategies.info-lower-bound` (technique) — log₂ counting of distinguishable outcomes

## 52. quant-puzzles.classics — Classic Brainteasers
summary: The canonical worked puzzles — coins and scales, prisoners and boxes, fuses, jugs, ants, and egg drops.
topics:
- 12-coin counterfeit with 3 weighings (info bound + scheme)
- Fuses: measure 45 minutes with two 60-minute fuses
- Water jugs and gcd
- Bridge crossing with a torch (17 minutes)
- 100 prisoners & boxes: cycle-following beats random (~31%)
- Prisoners & light bulb (counter protocol)
- Hat puzzles: parity coding for guaranteed saves
- Ants on a stick: pass-through = identity swap
- Chameleons: invariant mod 3
- Egg drop: minimize worst-case drops (n(n+1)/2 ≥ 100 → 14)
- Mislabeled jars: one sample suffices
- Burning-rope, camel-and-bananas (light)
spine:
- `quant-puzzles.classics.coin-weighing` (example) — 12 coins in 3 weighings
- `quant-puzzles.classics.prisoners-boxes` (example) — the cycle-structure escape
- `quant-puzzles.classics.ants-stick` (example) — collisions are relabelings
- `quant-puzzles.classics.egg-drop` (example) — worst-case minimization with 2 eggs
- `quant-puzzles.classics.hat-parity` (example) — one bit saves n−1 prisoners

## 53. quant-puzzles.prob-paradoxes — Probability Paradoxes
summary: Where intuition breaks — Monty Hall, boy–girl, two envelopes, St. Petersburg, Simpson, and the airplane seat.
topics:
- Monty Hall (switch: 2/3), and why the host's knowledge matters
- Boy–girl paradox; the Tuesday-boy variant (conditioning fineness)
- Bertrand's box / three cards (2/3, not 1/2)
- Airplane seat problem (answer 1/2, the two-absorbing-states argument)
- Two envelopes: where the 5/4 argument breaks
- St. Petersburg: infinite EV, finite willingness to pay
- Simpson's paradox with a worked table; lurking aggregation in PnL attribution
- Base-rate neglect recap (relates disease test)
- Sleeping-beauty style ambiguity (prominence 0, light)
spine:
- `quant-puzzles.prob-paradoxes.monty-hall` (example) — switch, and the mechanism that makes it so
- `quant-puzzles.prob-paradoxes.boy-girl` (example) — how the sampling protocol changes the answer
- `quant-puzzles.prob-paradoxes.airplane-seat` (example) — the 1/2 by symmetry of the two fixed points
- `quant-puzzles.prob-paradoxes.two-envelopes` (example) — the broken expectation argument
- `quant-puzzles.prob-paradoxes.st-petersburg` (example) — unbounded EV meets bounded utility
- `quant-puzzles.prob-paradoxes.simpson` (example) — aggregation reverses comparisons

## 54. quant-puzzles.nim-games — Take-Away & Combinatorial Games
summary: Games you can solve outright — N/P positions, the Nim XOR theorem, races to N, and strategy stealing.
topics:
- Positions and moves; N-positions vs P-positions; backward labelling
- Race to N (subtraction games): the modular pattern
- Nim and the XOR theorem (statement + how to play)
- Mirroring/symmetry wins (two piles equal: second player)
- Strategy stealing (chomp: first player wins, nonconstructively)
- Sprague–Grundy pointer (prominence 0)
spine:
- `quant-puzzles.nim-games.np-positions` (definition) — losing/winning positions by backward labelling
- `quant-puzzles.nim-games.race-to-n` (example) — mod-(k+1) control
- `quant-puzzles.nim-games.nim-xor` (theorem) — XOR of pile sizes decides Nim
- `quant-puzzles.nim-games.strategy-stealing` (technique) — existence of a first-player win without a strategy

# quant-programming — Programming & Algorithms
summary: The coding round for quants — complexity, the data structures that matter, algorithmic patterns, and randomized algorithms with probability inside.

## 55. quant-programming.complexity — Complexity & Computation
summary: Costing computation — big-O, growth rates, amortized costs, hashing's expected O(1), and floating-point traps.
topics:
- Big-O/Ω/Θ; dominant terms; common growth rates ranked
- log n intuition (halving); n log n from divide-and-conquer
- Amortized analysis (dynamic array doubling)
- Hashing: expected O(1) lookups; collisions and the birthday bound
- Space–time tradeoffs
- Floating point: representation, catastrophic cancellation, comparing with tolerance, summation order (Kahan pointer)
- Integer overflow awareness
spine:
- `quant-programming.complexity.big-o` (definition) — asymptotic growth notation
- `quant-programming.complexity.growth-ranking` (proposition) — the ladder from O(1) to O(n!)
- `quant-programming.complexity.amortized` (definition) — doubling arrays average to O(1)
- `quant-programming.complexity.hashing-cost` (proposition) — expected O(1), and the birthday caveat
- `quant-programming.complexity.floating-point` (proposition) — what doubles can and cannot represent

## 56. quant-programming.data-structures — Data Structures
summary: Choosing the right container — arrays, hash maps, heaps, stacks and trees, and the streaming classics they unlock.
topics:
- Array vs linked list; locality
- Hash map/set: the default answer, and when it fails (ordering, worst case)
- Heap/priority queue; top-k pattern
- Running median with two heaps (the classic)
- Stack and queue; monotonic stack pattern (light)
- Binary search tree / sorted structures; when order queries matter
- LRU cache (hash map + doubly linked list)
- Choosing structures for streaming data
spine:
- `quant-programming.data-structures.hash-map` (definition) — O(1) key–value lookup and its limits
- `quant-programming.data-structures.heap` (definition) — priority queue operations and costs
- `quant-programming.data-structures.running-median` (example) — two heaps balanced
- `quant-programming.data-structures.top-k` (technique) — a size-k heap over a stream
- `quant-programming.data-structures.lru` (example) — eviction in O(1)

## 57. quant-programming.algorithms — Algorithmic Patterns
summary: The recurring solves — binary search (including on the answer), sorting facts, two pointers, dynamic programming, and graph traversal.
topics:
- Binary search; search on the answer space (min feasible x)
- Sorting: n log n comparison lower bound (info-theoretic); when counting sort beats it
- Two pointers / sliding window
- Prefix sums; Kadane's max subarray
- Dynamic programming: overlapping subproblems, memo vs tabulation (uses recurrences)
- Classic DPs: coin change, egg drop revisited, grid paths (ties Catalan)
- BFS/DFS; shortest path in unweighted graphs; state-space search of puzzles
- Greedy with exchange argument (light)
- Reservoir of patterns: when interviewers say "optimize"
spine:
- `quant-programming.algorithms.binary-search` (technique) — halve the search space, including on answers
- `quant-programming.algorithms.sorting-lower-bound` (theorem) — Ω(n log n) by counting leaves
- `quant-programming.algorithms.two-pointers` (technique) — linear scans with two indices
- `quant-programming.algorithms.dp` (technique) — cache overlapping subproblems
- `quant-programming.algorithms.bfs-dfs` (technique) — layer vs depth exploration
- `quant-programming.algorithms.prefix-sums` (technique) — O(1) range sums after O(n) prep

## 58. quant-programming.randomized — Randomized Algorithms
summary: Probability inside the code — shuffling, reservoir sampling, generating distributions, rand7-from-rand5, and expected-case analysis.
topics:
- Fisher–Yates shuffle: uniform permutations, and how naive shuffles fail
- Reservoir sampling: uniform k-of-stream with proof for k=1
- Sampling from discrete distributions (CDF/inverse method in code)
- rand7 from rand5: rejection on a 5×5 grid
- Fair coin from biased (von Neumann); biased from fair
- Estimating π by simulation (ties Monte Carlo)
- Randomized quicksort: expected n log n via indicators/harmonic numbers
- Random tie-breaking / hashing as randomization (light)
spine:
- `quant-programming.randomized.fisher-yates` (technique) — the correct uniform shuffle
- `quant-programming.randomized.reservoir` (technique) — sample a stream of unknown length
- `quant-programming.randomized.rand7-from-rand5` (example) — rejection sampling on the grid
- `quant-programming.randomized.von-neumann` (example) — fair flips from a biased coin
- `quant-programming.randomized.quicksort-expected` (example) — E[comparisons] = 2n ln n via indicators
