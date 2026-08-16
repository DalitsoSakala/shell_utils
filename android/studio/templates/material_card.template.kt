import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp

/**
 * A Material 3 card that groups related content in a contained surface.
 *
 * It is clickable via [onClick]. Swap the sample Title/Body text for your
 * own content, or drop them and use the card's content slot directly.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun $Name$Card(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Card(
        onClick = onClick,
        modifier = modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "$Title$",
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                text = "$Body$",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            $END$
        }
    }
}

/** Preview of the card. */
@Preview(showBackground = true)
@Composable
private fun $Name$CardPreview() {
    MaterialTheme {
        $Name$Card(onClick = {})
    }
}
