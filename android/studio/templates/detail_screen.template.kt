import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Card
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp

/**
 * Generic detail screen for any item type [T].
 *
 * Renders a [details] list as label/value rows inside a card, and leaves a
 * [content] slot for screen-specific sections below the card. The top bar
 * back arrow invokes [onBack].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun <T> $Name$DetailScreen(
    item: T,
    details: List<Pair<String, String>> = emptyList(),
    onBack: () -> Unit = {},
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.(T) -> Unit = {},
) {
    // Root scaffold: centered top bar with a back arrow, scrollable content.
    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text(stringResource(id = R.string.$ScreenTitle$)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(id = R.string.back),
                        )
                    }
                },
            )
        },
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .padding(innerPadding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
        ) {
            // Card of label/value rows; populate them via the details list.
            if (details.isNotEmpty()) {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(horizontal = 16.dp)) {
                        details.forEachIndexed { index, (label, value) ->
                            DetailRow(label = label, value = value)
                            if (index < details.lastIndex) HorizontalDivider()
                        }
                    }
                }
                Spacer(modifier = Modifier.height(16.dp))
            }
            // Custom content below the card, scoped to the item.
            content(item)
        }
    }
}

/** Single label/value row used by the detail card. */
@Composable
private fun DetailRow(label: String, value: String, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 12.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyLarge,
        )
    }
}

/** Preview of the detail screen with sample data. */
@Preview(showBackground = true)
@Composable
private fun $Name$DetailScreenPreview() {
    MaterialTheme {
        $Name$DetailScreen(
            item = "Sample item",
            details = listOf(
                "Label 1" to "Value 1",
                "Label 2" to "Value 2",
            ),
            onBack = {},
        )
    }
}
