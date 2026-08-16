import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path

/**
 * Retrofit service definition for the $endpoint$ resource.
 *
 * All methods are suspend functions, so the repository implementation can
 * call them directly inside its coroutines.
 */
interface $Api$ {
    /** Fetches the full collection. */
    @GET("$endpoint$")
    suspend fun get$Name$s(): List<$Dto$>

    /** Fetches a single item by id. */
    @GET("$endpoint$/{id}")
    suspend fun get$Name$ById(@Path("id") id: Long): $Dto$

    /** Creates a new item server-side. */
    @POST("$endpoint$")
    suspend fun create$Name$(@Body body: $Dto$): $Dto$

    /** Deletes the item with the given id server-side. */
    @DELETE("$endpoint$/{id}")
    suspend fun delete$Name$(@Path("id") id: Long)
}
