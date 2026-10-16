import Testing
@testable import UttrflowCore

@Suite struct ZProbe {
    @Test func probe() {
        let secrets = [
            "I changed the password to Zx81kLm2Qp yesterday",
            "the password was Zx81kLm2Qp",
            "new password will be Zx81kLm2Qp",
            "reset the wifi password to Zx81kLm2Qp",
            "password -> Zx81kLm2Qp",
            "password - Zx81kLm2Qp",
            "password (temporary): Zx81kLm2Qp",
            "Your temporary password: Zx81kLm2Qp",
            "login with password Zx81kLm2Qp",
            "use token Zx81kLm2QpRt7 for the API",
            "the secret key = Zx81kLm2QpRt7",
            "the secret is Zx81kLm2QpRt7",
            "pin code 4817",
            "Password:\nZx81kLm2Qp",
            "<password>Zx81kLm2Qp</password>",
            "<apiKey>Zx81kLm2QpRt7Ab</apiKey>",
            "password&#61;Zx81kLm2Qp",
            "password\tZx81kLm2Qp",
            "PASSWORD   Zx81kLm2Qp",
            "p a s s w o r d : Zx81kLm2Qp",
            "password: Zx81kLm2Qp",
            "pass=Zx81kLm2Qp",
            "passwd Zx81kLm2Qp",
            "Pw: Zx81kLm2Qp",
            "creds: alice / Zx81kLm2Qp",
            "wifi: HomeNet pass Zx81kLm2Qp",
            "the code to unlock is 4817",
            "unlock code: 4817",
            "my pin is four eight one seven",
            "password is correct horse battery staple",
            "the passphrase is purple monkey dishwasher",
        ]
        let plain = [
            "I forgot my password to the portal",
            "the password was reset by IT",
            "change the password to something stronger",
            "use a token of appreciation",
            "pin the post to the top",
            "secret key ingredient is patience",
            "the code was reviewed by Priya",
            "key is under the mat",
        ]
        for s in secrets where !SecretShapes.matches(s) { print("MISS-SECRET: \(s)") }
        for s in plain where SecretShapes.matches(s) { print("FALSE-POS: \(s)") }
    }
}
