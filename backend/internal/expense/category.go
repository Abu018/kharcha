package expense

import (
	"strings"

	"my_app/backend/internal/models"
)

const (
	unknownCategory = "Unknown"
	incomeCategory  = "Income"
)

// Categories lists every category a transaction can have.
var Categories = []string{
	"Food", "Groceries", "Transport", "Shopping", "Bills", "Entertainment",
	"Health", "Transfers", incomeCategory, "Other", unknownCategory,
}

// IsCategory reports whether c is one of Categories, matched exactly.
func IsCategory(c string) bool {
	for _, known := range Categories {
		if c == known {
			return true
		}
	}
	return false
}

// keywordRules are checked in order against the vendor and UPI ID, so more
// specific words (e.g. "jiohotstar") must come before broader ones ("jio").
var keywordRules = []struct {
	category string
	keywords []string
}{
	{"Entertainment", []string{
		"jiohotstar", "hotstar", "netflix", "spotify", "prime video", "sonyliv", "zee5",
		"youtube", "bookmyshow", "pvr", "inox", "playo", "playstore", "steam",
	}},
	{"Groceries", []string{
		"zepto", "blinkit", "grofers", "bigbasket", "instamart", "dmart",
		"jiomart", "hyper market", "hypermarket", "supermarket", "super market",
		"grand fresh", "kirana", "hap daily", "milk", "dairy", "vegetable",
	}},
	{"Food", []string{
		"swiggy", "zomato", "eatsure", "dominos", "domino's", "pizza", "kfc",
		"mcdonald", "burger", "starbucks", "cafe", "coffee", "bakery", "iyengar",
		"restaurant", "hotel", "biryani", "juice", "tea", "chai", "food",
		"kitchen", "dhaba", "bar & grill",
	}},
	{"Transport", []string{
		"uber", "ola", "rapido", "namma yatri", "metro", "irctc", "redbus",
		"fastag", "petrol", "fuel", "indian oil", "bharat petroleum", "hpcl",
		"shell", "parking", "auto service", "indigo", "air india",
	}},
	{"Health", []string{
		"pharmacy", "pharma", "medical", "apollo", "medplus", "1mg", "netmeds",
		"pharmeasy", "hospital", "clinic", "diagnostic", "lab",
	}},
	{"Shopping", []string{
		"amazon", "flipkart", "myntra", "ajio", "meesho", "nykaa", "tata cliq",
		"decathlon", "ikea", "croma", "reliance digital", "style", "fashion",
		"trends", "lifestyle",
	}},
	{"Bills", []string{
		"airtel", "jio", "vodafone", "vi prepaid", "bsnl", "act fibernet",
		"bescom", "electricity", "water", "gas", "broadband", "recharge",
		"insurance", "lic", "rent", "google", "apple.com", "icloud",
	}},
}

// keywordCategory returns the category for well-known vendors, or "" when
// none of the keywords match.
func keywordCategory(tx *models.Transaction) string {
	text := " " + strings.ToLower(tx.Vendor+" "+tx.VendorUPI) + " "
	for _, rule := range keywordRules {
		for _, k := range rule.keywords {
			if containsWord(text, k) {
				return rule.category
			}
		}
	}
	return ""
}

// containsWord matches k only at word starts, so "ola" does not match
// "Cola" and "tea" does not match "Steam".
func containsWord(text, k string) bool {
	for i := 0; ; {
		j := strings.Index(text[i:], k)
		if j < 0 {
			return false
		}
		j += i
		if j == 0 || !isLetter(text[j-1]) {
			return true
		}
		i = j + 1
	}
}

func isLetter(b byte) bool {
	return b >= 'a' && b <= 'z'
}
