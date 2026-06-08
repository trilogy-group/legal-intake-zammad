import { config } from "dotenv";
import * as path from "path";
import { dirname } from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const envPath = process.env.ZAMMAD_ENV_DIR
  ? path.join(process.env.ZAMMAD_ENV_DIR, ".env")
  : path.join(__dirname, "..", "staging", ".env");
config({ path: envPath });

const ZAMMAD_URL = process.env.ZAMMAD_URL;
const ZAMMAD_TOKEN = process.env.ZAMMAD_TOKEN;

// Helper function to replace "article" with "comment" preserving case
function replaceArticleWithComment(text: string): string {
  return text
    .replace(/\bArticle\b/g, "Comment") // Article -> Comment
    .replace(/\barticle\b/g, "comment") // article -> comment
    .replace(/\bArticles\b/g, "Comments") // Articles -> Comments
    .replace(/\barticles\b/g, "comments"); // articles -> comments
}

async function updateArticleTranslations() {
  try {
    console.log("Fetching current translations from Zammad...\n");

    // Fetch translations from API
    const fetchResponse = await fetch(`${ZAMMAD_URL}/api/v1/translations`, {
      headers: {
        Authorization: `Bearer ${ZAMMAD_TOKEN}`,
        "Content-Type": "application/json",
      },
    });

    if (!fetchResponse.ok) {
      throw new Error(
        `Failed to fetch translations: HTTP ${fetchResponse.status}`
      );
    }

    const allTranslations = await fetchResponse.json();

    // Filter for Article translations
    const translations = allTranslations.filter(
      (t: any) =>
        (t.source && t.source.toLowerCase().includes("article")) ||
        (t.target && t.target.toLowerCase().includes("article"))
    );

    console.log(`Found ${translations.length} translations with "Article"\n`);

    console.log("Updating Article → Comment translations\n");
    console.log("=".repeat(70));

    let successCount = 0;
    let failCount = 0;
    let skippedCount = 0;

    for (const translation of translations) {
      const newTarget = replaceArticleWithComment(translation.target);

      // Skip if no change needed
      if (newTarget === translation.target) {
        console.log(`\n${translation.id}. "${translation.source}"`);
        console.log(`  ⏭️  Skipped (no "article" found)`);
        skippedCount++;
        continue;
      }

      console.log(`\n${translation.id}. "${translation.source}"`);
      console.log(`  Old: "${translation.target}"`);
      console.log(`  New: "${newTarget}"`);

      try {
        const response = await fetch(
          `${ZAMMAD_URL}/api/v1/translations/${translation.id}`,
          {
            method: "PUT",
            headers: {
              Authorization: `Bearer ${ZAMMAD_TOKEN}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              ...translation,
              target: newTarget,
            }),
          }
        );

        if (response.ok) {
          console.log(`  ✅ Updated`);
          successCount++;
        } else {
          const errorText = await response.text();
          console.log(
            `  ❌ Failed (${response.status}): ${errorText.substring(0, 100)}`
          );
          failCount++;
        }
      } catch (error) {
        console.log(`  ❌ Error: ${error}`);
        failCount++;
      }

      // Small delay to avoid rate limiting
      await new Promise((resolve) => setTimeout(resolve, 200));
    }

    console.log("\n" + "=".repeat(70));
    console.log(`\n📊 Summary:`);
    console.log(`   ✅ Successfully updated: ${successCount}`);
    console.log(`   ❌ Failed: ${failCount}`);
    console.log(`   ⏭️  Skipped: ${skippedCount}`);
    console.log(`\n✅ Translation update complete!`);
    console.log("\n⚠️  Next steps:");
    console.log("   1. Clear browser cache or hard refresh (Ctrl+Shift+R)");
    console.log("   2. Log out and back in to Zammad");
    console.log('   3. Check the UI - "Article" should now show as "Comment"');
  } catch (error) {
    console.error("Error:", error);
  }
}

updateArticleTranslations();
