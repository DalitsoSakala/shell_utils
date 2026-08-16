import kotlinx.coroutines.flow.Flow

/**
 * Repository contract for $Name$ (domain layer).
 *
 * Screens and use cases depend on this interface rather than on a concrete
 * implementation, so the data source can be swapped without UI changes.
 */
interface $Repository$ {
    /** Emits the full collection and re-emits whenever the cache changes. */
    fun get$Name$s(): Flow<$Name$>

    /** Returns a single item by id, or null when it does not exist. */
    suspend fun get$Name$ById(id: Long): $Name$?

    /** Inserts or replaces an item in the local cache. */
    suspend fun upsert$Name$($item$: $Name$)

    /** Removes an item from the local cache. */
    suspend fun delete$Name$(id: Long)
}
