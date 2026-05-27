//
//  StyledButton.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/24/26.
//
import SwiftUI

struct StyledButton: View {
    var title: String
    var systemName: String?
    var type: String?
    var action: () -> Void?

    var body: some View {
        Button(action: {
            action()
        }) {
            ZStack {
                if type == "delete" {

                    Color(red: 208/255, green: 0/255, blue: 0/255)
                    LinearGradient(gradient: Gradient(colors: [.white.opacity(0.2), .white.opacity(0)]), startPoint: .top, endPoint: .center)
                } else {
                    Image("button")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                HStack {

                    if systemName != nil {
                        Image(systemName: systemName!)
                            .foregroundStyle(.white)
                    }
                    Text(title)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 300, maxHeight: 50)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.5), lineWidth: 4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .contentShape(RoundedRectangle(cornerRadius: 24))

    }
}

#Preview {
    StyledButton(
        title: "allow access to photos to start",
        systemName: "heart.fill",
        type: "delete"
    ) {
        print("fireeee")
    }
}
