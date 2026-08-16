import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.NavGraphBuilder
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import org.koin.androidx.compose.viewModel

/** Central place for route strings, shared by the graph and navigation calls. */
object $Name$Routes {
    const val LIST = "$routeList$"
    const val DETAIL = "$routeDetail$/{id}"

    /** Builds the detail route for a concrete id. */
    fun detail(id: Long) = "$routeDetail$/$id"
}

/**
 * Nestable graph builder: adds these destinations to any [NavHost].
 *
 * Two ways to use it:
 *  - Embed it inside another NavHost's builder lambda:
 *    `NavHost(...) { $Name$Graph(navController) }`
 *  - Or register it as a nested graph with its own start destination:
 *    `navigation(startDestination = $Name$Routes.LIST, route = "$Name$Graph") {
 *        $Name$Graph(navController)
 *    }`
 * Each destination resolves its ViewModel through Koin with [viewModel],
 * which requires `koin-androidx-compose` and a started Koin app.
 *
 * Navigation architecture:
 *
 *  ┌─────────────────────────────────────┐
 *  │  $Name$NavHost (@Composable)       │  ← root host used by setContent
 *  └───────────────────┬─────────────────┘
 *                      │ rememberNavController()
 *                      ▼
 *  ┌─────────────────────────────────────┐
 *  │  NavHost (startDestination = LIST)  │
 *  └───────────────────┬─────────────────┘
 *                      │ route strings from $Name$Routes
 *                      ▼
 *  ┌─────────────────────────────────────┐
 *  │  LIST   : "$routeList$"            │
 *  │    $ListScreen$ ⇄ $ListViewModel$ (Koin)  │
 *  │         │ navigate(detail(id))      │
 *  │         ▼                           │
 *  │  DETAIL : "$routeDetail$/{id}"     │
 *  │    $DetailScreen$ ⇄ $DetailViewModel$ (Koin) │
 *  └─────────────────────────────────────┘
 *
 * One destination = one route → composable → ViewModel. Routes are
 * centralized in $Name$Routes so the graph and every navigation call
 * share a single source of truth.
 */
fun NavGraphBuilder.$Name$Graph(
    navController: NavHostController,
) {
    // List destination: the app entry point.
    composable(route = $Name$Routes.LIST) {
        val listViewModel: $ListViewModel$ by viewModel()
        $ListScreen$(
            onNavigateToDetail = { id -> navController.navigate($Name$Routes.detail(id)) },
        )
    }
    // Detail destination: receives its id as a typed navigation argument.
    composable(
        route = $Name$Routes.DETAIL,
        arguments = listOf(navArgument("id") { type = NavType.LongType }),
    ) {
        val detailViewModel: $DetailViewModel$ by viewModel()
        $DetailScreen$(
            onBack = { navController.popBackStack() },
        )
    }
    $END$
}

/**
 * Root host for standalone usage: `setContent { $Name$NavHost() }`.
 *
 * For nesting, skip this host and call `$Name$Graph(navController)` inside a
 * larger NavHost instead.
 */
@Composable
fun $Name$NavHost(
    navController: NavHostController = rememberNavController(),
    modifier: Modifier = Modifier,
) {
    NavHost(
        navController = navController,
        startDestination = $Name$Routes.LIST,
        modifier = modifier,
    ) {
        $Name$Graph(navController)
    }
}
