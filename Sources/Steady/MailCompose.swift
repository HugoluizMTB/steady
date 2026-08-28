import SwiftUI

struct MailComposeSheet: View {
    let store: MailStore
    var initialTo = ""
    var initialSubject = ""
    let onClose: () -> Void

    @State private var to = ""
    @State private var subject = ""
    @State private var bodyText = ""
    @State private var failed = false

    private var canSend: Bool { to.contains("@") && !store.sending }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(SteadyPalette.line).frame(height: 1)
            VStack(spacing: 10) {
                LabeledField(label: "To", text: $to)
                LabeledField(label: "Subject", text: $subject)
                TextEditor(text: $bodyText)
                    .font(.system(size: 13)).foregroundStyle(SteadyPalette.ink)
                    .scrollContentBackground(.hidden).padding(8)
                    .frame(minHeight: 170)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(SteadyPalette.line))
                if failed {
                    Text("Couldn't send. Check the address or Mail automation permission.")
                        .font(.system(size: 11)).foregroundStyle(SteadyPalette.negative)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            Spacer()
        }
        .frame(width: 460, height: 430)
        .background(SteadyPalette.canvas)
        .onAppear {
            if to.isEmpty { to = initialTo }
            if subject.isEmpty { subject = initialSubject }
        }
    }

    private var header: some View {
        HStack {
            Button("Cancel", action: onClose).buttonStyle(.plain).foregroundStyle(SteadyPalette.muted)
            Spacer()
            Text("New message").font(.system(size: 13, weight: .semibold)).foregroundStyle(SteadyPalette.ink)
            Spacer()
            Button(action: submit) {
                if store.sending { ProgressView().controlSize(.small) } else { Text("Send") }
            }
            .buttonStyle(.plain).font(.system(size: 13, weight: .semibold))
            .foregroundStyle(canSend ? SteadyPalette.mint : SteadyPalette.muted)
            .disabled(!canSend)
        }
        .padding(14)
    }

    private func submit() {
        failed = false
        store.send(to: to.trimmingCharacters(in: .whitespaces), subject: subject, body: bodyText) { ok in
            if ok { onClose() } else { failed = true }
        }
    }
}

private struct LabeledField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(SteadyPalette.muted).frame(width: 56, alignment: .leading)
            TextField("", text: $text).textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(SteadyPalette.ink)
        }
        .padding(.horizontal, 10).frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SteadyPalette.line))
    }
}

struct MailMessageView: View {
    let store: MailStore
    let message: MailMessage

    @State private var showingReply = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(SteadyPalette.line).frame(height: 1)
            metadata
            Rectangle().fill(SteadyPalette.line).frame(height: 1)
            ScrollView {
                if store.loadingBody {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    Text(store.openBody.isEmpty ? "(No text content)" : store.openBody)
                        .font(.system(size: 13)).foregroundStyle(Color(hex: "d4d6da"))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            }
        }
        .frame(width: 580, height: 540)
        .background(SteadyPalette.canvas)
        .sheet(isPresented: $showingReply) {
            MailComposeSheet(store: store, initialTo: message.senderEmail, initialSubject: replySubject) { showingReply = false }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { store.closeOpen() } label: {
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(SteadyPalette.muted)
            }
            .buttonStyle(.plain)
            Text(message.subject.isEmpty ? "(No subject)" : message.subject)
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(SteadyPalette.ink).lineLimit(2)
            Spacer(minLength: 8)
            Button { showingReply = true } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left.fill").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "102019")).padding(.horizontal, 12).frame(height: 28)
                    .background(Capsule().fill(SteadyPalette.mint))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
    }

    private var metadata: some View {
        HStack(spacing: 8) {
            Text(message.senderName).font(.system(size: 12, weight: .medium)).foregroundStyle(SteadyPalette.ink)
            Text(message.senderEmail).font(.system(size: 11)).foregroundStyle(SteadyPalette.muted)
            Spacer(minLength: 8)
            Text(message.dateText).font(.system(size: 11)).foregroundStyle(SteadyPalette.muted)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var replySubject: String {
        message.subject.lowercased().hasPrefix("re:") ? message.subject : "Re: \(message.subject)"
    }
}
