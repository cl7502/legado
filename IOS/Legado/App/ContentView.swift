import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "book.fill")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Legado iOS")
                .font(.largeTitle)
                .padding()
            Text("Ready for Development")
                .font(.subheadline)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
