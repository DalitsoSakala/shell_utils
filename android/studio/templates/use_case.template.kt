import kotlinx.coroutines.flow.Flow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Use case that observes the full collection.
 *
 * Use cases hold business logic and depend on a repository interface, which
 * keeps ViewModels lean. Call it directly: `getItemsUseCase()`.
 */
@Singleton
class Get$Name$sUseCase @Inject constructor(
    private val repository: $Repository$,
) {
    operator fun invoke(): Flow<$Name$> = repository.get$Name$s()
}
