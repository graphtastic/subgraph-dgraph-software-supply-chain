// Extractor: GUAC Mesh → RDF N-Quads for Dgraph (WIP)
// This script is a functional diagnostic tool to test connectivity and data fetching
// from the GraphQL Mesh endpoint.

import fetch from 'node-fetch';

const MESH_ENDPOINT = process.env.MESH_ENDPOINT || 'http://localhost:4000/graphql';

// A simple query to fetch some artifacts.
const ARTIFACT_QUERY = `
  query GetArtifacts {
    artifacts(artifactSpec: {}) {
      id
      algorithm
      digest
    }
  }
`;

async function main() {
  console.log(`🚀 Graphtastic Extractor (Diagnostic Mode)`);
  console.log(`📌 Targeting Mesh endpoint: ${MESH_ENDPOINT}`);

  try {
    console.log('\n\uD83D\uDD0D Sending query to Mesh...');
    const response = await fetch(MESH_ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: ARTIFACT_QUERY }),
    });

    if (!response.ok) {
      const errorBody = await response.text();
      throw new Error(`HTTP error! Status: ${response.status} ${response.statusText}\nBody: ${errorBody}`);
    }

    const jsonResponse: any = await response.json();

    if (jsonResponse.errors) {
      console.error('❌ GraphQL query returned errors:');
      console.error(JSON.stringify(jsonResponse.errors, null, 2));
      process.exit(1);
    }

    console.log('✅ Successfully received data from Mesh:');
    console.log(JSON.stringify(jsonResponse.data, null, 2));

    // TODO: Implement the transformation from this JSON data to RDF N-Quads.
    console.log('\n💾 (WIP) RDF transformation step would happen here.');
    console.log('✨ Diagnostic run complete.');

  } catch (error) {
    console.error('❌ An error occurred during extraction:');
    console.error(error);
    process.exit(1);
  }
}

main();