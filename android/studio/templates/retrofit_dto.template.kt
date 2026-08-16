import com.google.gson.annotations.SerializedName

/**
 * DTO (data transfer object) matching the remote $Name$ payload.
 *
 * Field names map to the server JSON with [SerializedName]. Keep it separate
 * from the domain model because server shapes change more often.
 */
data class $Dto$(
    @SerializedName("id")
    val id: Long,

    @SerializedName("$fieldOne$")
    val $FieldOne$: String?,

    @SerializedName("$fieldTwo$")
    val $FieldTwo$: String?,
)
